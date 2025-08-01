tune_grid_loop <- function(
  resamples,
  grid,
  workflow,
  param_info,
  metrics,
  eval_time,
  control
) {
  if (is.null(grid)) {
    grid <- tibble::tibble()
  }

  mtr_info <- tibble::as_tibble(metrics)

  control <- update_parallel_over(control, resamples, grid)

  # For last_fit, we want to keep the RNG stream as-is to maintain reproducibility
  # with manual execution. Otherwise, generate parallel seeds even if work is
  # being executed sequentially. `resamples$id` is set in `last_fit_workflow`.
  if (all(resamples$id == "train/test split")) {
    resamples$.seeds <- purrr::map(resamples$id, \(x) integer(0))
  } else {
    # Make and set the worker/process seeds if workers get resamples
    resamples$.seeds <- get_parallel_seeds(nrow(resamples))
  }

  # We'll significantly alter the rsample object but will need it intact later;
  # Make a copy and save some information before proceeding
  rset_info <- pull_rset_attributes(resamples)
  split_args <- rsample::.get_split_args(resamples)

  resamples <- new_bare_tibble(resamples)
  # Break it up row-wise to facilitate mapping/parallelism
  resamples <- vec_list_rowwise(resamples)

  # add an on.exit(); esc puts us in code

  # Notes on debugging:
  # 1. You can set `options(future.debug = TRUE)` to help
  # 2. If you are debugging loop_over_all_stages, use the control option
  #    `allow_par = FALSE`; that will use `lapply()` so that you can see output.

  # ------------------------------------------------------------------------------

  # fmt: skip
  tm_pkgs <- c("rsample", "workflows", "hardhat", "tune", "parsnip", "tailor",
               "yardstick")
  load_pkgs <- c(required_pkgs(workflow), control$pkgs, tm_pkgs)
  load_pkgs <- unique(load_pkgs)

  par_opt <- list()

  # ----------------------------------------------------------------------------
  # Collect "static" data into a single object for a cleaner interface

  static <- make_static(
    workflow,
    param_info = param_info,
    grid = grid,
    metrics = metrics,
    eval_time = eval_time,
    split_args = split_args,
    control = control,
    pkgs = load_pkgs
  )

  # fmt: skip
  tm_pkgs <- c("rsample", "workflows", "hardhat", "tune", "parsnip", "tailor",
               "yardstick")
  load_pkgs <- c(required_pkgs(workflow), control$pkgs, tm_pkgs)
  load_pkgs <- unique(load_pkgs)

  par_opt <- list()

  # ----------------------------------------------------------------------------
  # Control execution

  # We'll make a call that defines how we iterate over resamples and grid points.
  # That call changes depending on the value of `control$parallel_over`. There
  # are two possible options:
  # - parallel_over == "resamples" means that we lapply() over the existing
  #   `resamples` object.
  # - parallel_over == "everything" means that we lapply() over the every
  #   combination of resamples x grid candidates. That index (called `inds`) has
  #   not been created at this point.
  #
  # We'll create `inds` only if needed and then use the same code to make the
  # call objects (`cl`) that will be executed in the current environment. `cl`
  # will contain a reference to either `resamples` or `inds` depending on the
  # `parallel_over` value in `control`.

  if (control$parallel_over == "everything") {
    # If multiple resamples but preprocessing is cheap (or just a validation set).
    # Loop over grid rows and splits
    candidates <- get_row_wise_grid(workflow, grid)

    # Break all combinations of resamples and candidates into a list of integers
    # for each combination.
    inds <- tidyr::crossing(s = seq_along(candidates), b = seq_along(resamples))

    # Split up for better processing
    inds <- vec_list_rowwise(inds)
  }

  strategy <- choose_framework(static$workflow, control)
  cl <- loop_call(control$parallel_over, strategy, par_opt)
  res <- rlang::eval_bare(cl)

  # ----------------------------------------------------------------------------
  # Separate results into different components

  res <- dplyr::bind_rows(res)

  outcome_names <- unique(unlist(res$outcome_names))
  res$outcome_names <- NULL

  resamples <- dplyr::bind_rows(resamples)
  id_cols <- grep("^id", names(resamples), value = TRUE)

  if (control$parallel_over == "resamples") {
    res <- dplyr::full_join(resamples, res, by = id_cols)
  } else {
    # Clean up for variable columns and make into a function
    pool_cols <- grep("^\\.", names(res), value = TRUE)
    res <- res |>
      dplyr::summarize(
        dplyr::across(dplyr::matches("^\\."), ~ list(purrr::list_rbind(.x))),
        .by = c(!!!id_cols)
      ) |>
      dplyr::full_join(resamples, by = id_cols)
  }

  res <- res |>
    dplyr::relocate(
      splits,
      dplyr::starts_with("id"),
      .metrics,
      .notes,
      dplyr::any_of(".predictions"),
      dplyr::any_of(".extracts")
    )

  res <-
    new_tune_results(
      x = res,
      parameters = param_info,
      metrics = metrics,
      eval_time = eval_time,
      eval_time_target = NULL,
      outcomes = outcome_names,
      rset_info = rset_info,
      workflow = workflow
    )

  res
}

vec_list_rowwise <- function(x) {
  vctrs::vec_split(x, by = 1:nrow(x))$val
}
