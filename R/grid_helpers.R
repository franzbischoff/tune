
predict_model <- function(new_data, orig_rows, workflow, grid, metrics,
                          submodels = NULL, metrics_info, eval_time = NULL) {

  model <- extract_fit_parsnip(workflow)

  forged <- forge_from_workflow(new_data, workflow)
  x_vals <- forged$predictors
  y_vals <- forged$outcomes

  # TODO patch since parsnip does not record the column names when Surv objects
  # are used with fit_xy()
  if (model$spec$mode == "censored regression") {
    model$preproc$y_var <- names(y_vals)
  }

  if (length(orig_rows) != nrow(x_vals)) {
    msg <- paste0(
      "Some assessment set rows are not available at ",
      "prediction time. "
    )

    if (has_preprocessor_recipe(workflow)) {
      msg <- paste0(
        msg,
        "Consider using `skip = TRUE` on any recipe steps that remove rows ",
        "to avoid calling them on the assessment set."
      )
    } else {
      msg <- paste0(
        msg,
        "Did your preprocessing steps filter or remove rows?"
      )
    }

    rlang::abort(msg)
  }

  # Determine the type of prediction that is required
  types <- unique(metrics_info$type)

  res <- NULL
  merge_vars <- c(".row", names(grid))

  for (type_iter in types) {
    # Regular predictions

    tmp_res <- predict_wrapper(model, x_vals, type_iter, eval_time)
    tmp_res$.row <- orig_rows
    tmp_res <- vctrs::vec_cbind(tmp_res, grid)


    if (!is.null(submodels)) {
      submod_length <- lengths(submodels)
      has_submodels <- any(submod_length > 0)

      if (has_submodels) {
        submod_param <- names(submodels)
        subgrid <- make_submod_arg(grid, model, submodels)

        tmp_sub <- predict_wrapper(model, x_vals, type_iter, eval_time, subgrid)
        tmp_sub$.row <- orig_rows
        tmp_sub <- unnest(tmp_sub, cols = dplyr::starts_with(".pred"))

        grid_bind <- grid
        grid_bind[, submod_param] <- NULL

        tmp_sub <- vctrs::vec_cbind(tmp_sub, grid_bind)
        rownames(tmp_sub) <- NULL
        tmp_sub <- dplyr::rename(tmp_sub, !!!make_rename_arg(grid, model, submodels))
        tmp_sub <- tmp_sub[, names(tmp_res)]

        tmp_res <- vec_rbind(tmp_sub, tmp_res)
      }
    }

    if (!is.null(res)) {
      res <- dplyr::full_join(res, tmp_res, by = merge_vars)
    } else {
      res <- tmp_res
    }

    rm(tmp_res)
  } # end type loop

  # Add outcome data
  y_vals$.row <- orig_rows
  res <- dplyr::full_join(res, y_vals, by = ".row")

  if (has_postprocessor(workflow)) {
    post <- extract_postprocessor(workflow)

    if (tailor::tailor_fully_trained(post)) {
      res <- predict(post, res)
    }
  }

  # Add implicitly grouped metric data, if applicable
  metrics_by <- get_metrics_by(metrics)
  if (has_metrics_by(metrics_by)) {
    new_data$.row <- orig_rows
    res <- dplyr::full_join(res, new_data[c(metrics_by, ".row")], by = ".row")
  }

  # Add case weights (if needed)
  if (has_case_weights(workflow)) {
    case_weights <- extract_case_weights(new_data, workflow)

    if (.use_case_weights_with_yardstick(case_weights)) {
      case_weights <- rlang::list2(!!case_weights_column_name() := case_weights)
      case_weights <- vctrs::new_data_frame(case_weights)
      case_weights <- dplyr::mutate(case_weights, .row = orig_rows)
      res <- dplyr::full_join(res, case_weights, by = ".row")
    }
  }


  res <- maybe_add_ipcw(res, model, types)

  if (!tibble::is_tibble(res)) {
    res <- tibble::as_tibble(res)
  }
  res
}

trim_ipcw <- function(x) {
  x$.weight_time <- NULL
  x$.pred_censored <- NULL
  x
}

maybe_add_ipcw <- function(.data, model, types) {
  if (!any(types == "survival")) {
    return(.data)
  }
  res <- parsnip::.censoring_weights_graf(model, .data)
  res$.pred <- purrr::map(res$.pred, trim_ipcw)
  res
}

#' Get time for analysis of dynamic survival metrics
#' @param metrics A metric set.
#' @param eval_time A vector of evaluation times.
#' @export
#' @keywords internal
get_metric_time <- function(metrics, eval_time) {
  info <- tibble::as_tibble(metrics)
  if (any(info$class == "dynamic_survival_metric")) {
    eval_time <- eval_time[1]
  } else {
    eval_time <- NULL
  }
  eval_time
}

predict_wrapper <- function(model, new_data, type, eval_time, subgrid = NULL) {
  if (is.null(subgrid)) {
    fn <- "predict.model_fit"
  } else {
    fn <- "multi_predict"
  }

  cl <-
    rlang::call2(
      fn,
      .ns = "parsnip",
      object = rlang::expr(model),
      new_data = rlang::expr(new_data),
      type = type)

  # Add in censored regression evaluation times (if needed)
  has_type <- type %in% c("survival", "hazard")
  if (model$spec$mode == "censored regression" & !is.null(eval_time) & has_type) {
    cl <- rlang::call_modify(cl, eval_time = eval_time)
  }

  # When there are sub-models:
  if (!is.null(subgrid)) {
    cl <- rlang::call_modify(cl, !!!subgrid)
  }
  res <- rlang::eval_tidy(cl)

  res
}

# ------------------------------------------------------------------------------

#' @export
#' @rdname tune-internal-functions
forge_from_workflow <- function(new_data, workflow) {
  blueprint <- workflow$pre$mold$blueprint

  forged <- hardhat::forge(new_data, blueprint, outcomes = TRUE)

  forged
}

make_submod_arg <- function(grid, model, submodels) {
  # Assumes only one submodel parameter per model
  real_name <-
    parsnip::get_from_env(paste(class(model$spec)[1], "args", sep = "_")) %>%
    dplyr::filter(has_submodel & engine == model$spec$engine) %>%
    dplyr::pull(parsnip)
  names(submodels) <- real_name
  submodels
}

make_rename_arg <- function(grid, model, submodels) {
  # Assumes only one submodel parameter per model
  real_name <-
    parsnip::get_from_env(paste(class(model$spec)[1], "args", sep = "_")) %>%
    dplyr::filter(has_submodel & engine == model$spec$engine) %>%
    dplyr::pull(parsnip)
  res <- list(real_name)
  names(res) <- names(submodels)
  res
}

get_metrics_by <- function(metric_set) {
  metrics <- attr(metric_set, "metrics")
  metrics_by <- purrr::map(metrics, attr, "by")
  unique(unlist(metrics_by, use.names = FALSE))
}

# metrics_by is the output of `get_metrics_by()`---it's assumed that wherever
# `has_metrics_by()` is needed, `get_metrics_by()` output will be needed too.
has_metrics_by <- function(metrics_by) {
  length(metrics_by) > 0
}

# ------------------------------------------------------------------------------

finalize_workflow_spec <- function(workflow, grid_model) {
  # Already finalized, nothing to tune
  if (ncol(grid_model) == 0L) {
    return(workflow)
  }

  spec <- extract_spec_parsnip(workflow)
  spec <- merge(spec, grid_model)$x[[1]]

  workflow <- set_workflow_spec(workflow, spec)

  workflow
}

#' @export
#' @rdname tune-internal-functions
finalize_workflow_preprocessor <- function(workflow, grid_preprocessor) {
  # Already finalized, nothing to tune
  if (ncol(grid_preprocessor) == 0L) {
    return(workflow)
  }

  recipe <- extract_preprocessor(workflow)
  recipe <- merge(recipe, grid_preprocessor)$x[[1]]

  workflow <- set_workflow_recipe(workflow, recipe)

  workflow
}

# ------------------------------------------------------------------------------

# For any type of tuning, and for fit-resamples, we generate a unified
# grid-info object which is a tibble with two layers of information:
#
# - The outer level has to do with preprocessor iteration. Really this only
#   applies to recipes, as they are the only preprocessor type that can be
#   tuned. These correspond to columns starting at `.iter_preprocessor` and
#   going through the last preprocessor tuning parameter.
# - The inner level has to do with the models that get fit per preprocessor.
#   It corresponds to the columns starting at `.iter_model` and going through
#   `.submodels`. This has been "minified" by `min_grid()`. The `$.submodels`
#   column contains all of the submodels that this parameter combination can
#   predict on.
#
# A single row of this tibble corresponds to a unique hyperparameter combination
# across both the preprocessor and model that has to be fit.
#
# `compute_grid_info()` returns a tibble with the following columns:
# .iter_preprocessor:
#   An integer vector of the current preprocessor iteration.
# .msg_preprocessor:
#   The message that is printed as we fit this preprocessor iteration.
# <preprocessor-tuning-columns>:
#   Zero or more columns outlining the recipes tuning parameter combinations.
# .iter_model:
#   An integer vector of the current model iteration within the current
#   `.iter_preprocessor` iteration.
# .iter_config:
#   A list column of character vectors containing `"Preprocessor<i>_Model<j>"`
#   to describe exactly which iteration we are on. Each submodel is treated
#   as its own unique model here, and has its own id.
# .msg_model:
#   The message that is printed as we fit this model iteration.
# <model-tuning-columns>:
#   Zero or more columns outlining the model tuning parameter combinations.
# .submodels:
#   A list column of lists. Each element contains zero of more submodels that
#   this particular parameter combination can predict for.
#
compute_grid_info <- function(workflow, grid) {
  # For `fit_resamples()`
  if (is.null(grid)) {
    out <- new_grid_info_resamples()
    return(out)
  }

  grid <- tibble::as_tibble(grid)

  parameters <- hardhat::extract_parameter_set_dials(workflow)
  parameters_model <- dplyr::filter(parameters, source == "model_spec")
  parameters_preprocessor <- dplyr::filter(parameters, source == "recipe")

  any_parameters_model <- nrow(parameters_model) > 0
  any_parameters_preprocessor <- nrow(parameters_preprocessor) > 0

  if (any_parameters_model) {
    if (any_parameters_preprocessor) {
      compute_grid_info_model_and_preprocessor(workflow, grid, parameters_model)
    } else {
      compute_grid_info_model(workflow, grid, parameters_model)
    }
  } else {
    if (any_parameters_preprocessor) {
      compute_grid_info_preprocessor(workflow, grid, parameters_model)
    } else {
      rlang::abort("Internal error: `workflow` should have some tunable parameters if `grid` is not `NULL`.")
    }
  }
}

# This generates a "dummy" grid_info object that has the same
# structure as a grid-info object with no tunable recipe parameters
# and no tunable model parameters.
new_grid_info_resamples <- function() {
  msgs_preprocessor <- new_msgs_preprocessor(
    i = 1L,
    n = 1L
  )

  msgs_model <- new_msgs_model(
    i = 1L,
    n = 1L,
    msgs_preprocessor = msgs_preprocessor
  )

  iter_config <- list("Preprocessor1_Model1")

  out <- tibble::new_tibble(list(
    .iter_preprocessor = 1L,
    .msg_preprocessor = msgs_preprocessor,
    .iter_model = 1L,
    .iter_config = iter_config,
    .msg_model = msgs_model,
    .submodels = list(list())
  ), nrow = length(msgs_model))

  out
}

compute_grid_info_preprocessor <- function(workflow,
                                           grid,
                                           parameters_model) {
  out <- grid

  n_preprocessors <- nrow(out)
  seq_preprocessors <- seq_len(n_preprocessors)

  # Preprocessor<i>_Model1
  ids <- format_with_padding(seq_preprocessors)
  iter_configs <- paste0("Preprocessor", ids, "_Model1")
  iter_configs <- as.list(iter_configs)

  # preprocessor <i>/<n>
  msgs_preprocessor <- new_msgs_preprocessor(
    i = seq_preprocessors,
    n = n_preprocessors
  )

  # preprocessor <i>/<n>, model 1/1
  msgs_model <- new_msgs_model(
    i = 1L,
    n = 1L,
    msgs_preprocessor = msgs_preprocessor
  )

  # Manually add .submodels column, which will always have empty lists
  submodels <- rep_len(list(list()), n_preprocessors)

  out <- tibble::add_column(
    .data = out,
    .iter_preprocessor = seq_preprocessors,
    .before = 1L
  )

  out <- tibble::add_column(
    .data = out,
    .msg_preprocessor = msgs_preprocessor,
    .after = ".iter_preprocessor"
  )

  # Add at the end
  out <- tibble::add_column(
    .data = out,
    .iter_model = 1L,
    .after = NULL
  )

  out <- tibble::add_column(
    .data = out,
    .iter_config = iter_configs,
    .after = ".iter_model"
  )

  out <- tibble::add_column(
    .data = out,
    .msg_model = msgs_model,
    .after = ".iter_config"
  )

  out <- tibble::add_column(
    .data = out,
    .submodels = submodels,
    .after = ".msg_model"
  )

  out
}

compute_grid_info_model <- function(workflow,
                                    grid,
                                    parameters_model) {
  spec <- extract_spec_parsnip(workflow)
  out <- min_grid(spec, grid)

  n_fit_models <- nrow(out)
  seq_fit_models <- seq_len(n_fit_models)

  # preprocessor 1/1
  msgs_preprocessor <- new_msgs_preprocessor(i = 1L, n = 1L)
  msgs_preprocessor <- rep(msgs_preprocessor, times = n_fit_models)

  # preprocessor 1/1, model <i_fit>/<n_fit>
  msgs_model <- new_msgs_model(
    i = seq_fit_models,
    n = n_fit_models,
    msgs_preprocessor = msgs_preprocessor
  )

  # Preprocessor1_Model<i>
  iter_configs <- compute_config_ids(out, "Preprocessor1")

  out <- tibble::add_column(
    .data = out,
    .iter_preprocessor = 1L,
    .before = 1L
  )

  out <- tibble::add_column(
    .data = out,
    .msg_preprocessor = msgs_preprocessor,
    .after = ".iter_preprocessor"
  )

  out <- tibble::add_column(
    .data = out,
    .iter_model = seq_fit_models,
    .after = ".msg_preprocessor"
  )

  out <- tibble::add_column(
    .data = out,
    .iter_config = iter_configs,
    .after = ".iter_model"
  )

  out <- tibble::add_column(
    .data = out,
    .msg_model = msgs_model,
    .after = ".iter_config"
  )

  out
}

compute_grid_info_model_and_preprocessor <- function(workflow,
                                                     grid,
                                                     parameters_model) {
  parameter_names_model <- parameters_model[["id"]]

  # Nest model parameters, keep preprocessor parameters outside
  out <- tidyr::nest(grid, data = dplyr::all_of(parameter_names_model))

  n_preprocessors <- nrow(out)
  seq_preprocessors <- seq_len(n_preprocessors)

  # preprocessor <i_pre>/<n_pre>
  msgs_preprocessor <- new_msgs_preprocessor(
    i = seq_preprocessors,
    n = n_preprocessors
  )

  out <- tibble::add_column(
    .data = out,
    .iter_preprocessor = seq_preprocessors,
    .before = 1L
  )

  out <- tibble::add_column(
    .data = out,
    .msg_preprocessor = msgs_preprocessor,
    .after = ".iter_preprocessor"
  )

  spec <- extract_spec_parsnip(workflow)

  ids_preprocessor <- format_with_padding(seq_preprocessors)
  ids_preprocessor <- paste0("Preprocessor", ids_preprocessor)

  model_grids <- out[["data"]]

  for (i in seq_preprocessors) {
    model_grid <- model_grids[[i]]

    model_grid <- min_grid(spec, model_grid)

    n_fit_models <- nrow(model_grid)
    seq_fit_models <- seq_len(n_fit_models)

    msg_preprocessor <- msgs_preprocessor[[i]]
    id_preprocessor <- ids_preprocessor[[i]]

    # preprocessor <i_pre>/<n_pre>, model <i_mod>/<n_mod>
    msgs_model <- new_msgs_model(
      i = seq_fit_models,
      n = n_fit_models,
      msgs_preprocessor = msg_preprocessor
    )

    # Preprocessor<i_pre>_Model<i>
    iter_configs <- compute_config_ids(model_grid, id_preprocessor)

    model_grid <- tibble::add_column(
      .data = model_grid,
      .iter_model = seq_fit_models,
      .before = 1L
    )

    model_grid <- tibble::add_column(
      .data = model_grid,
      .iter_config = iter_configs,
      .after = ".iter_model"
    )

    model_grid <- tibble::add_column(
      .data = model_grid,
      .msg_model = msgs_model,
      .after = ".iter_config"
    )

    model_grids[[i]] <- model_grid
  }

  out[["data"]] <- model_grids

  # Unnest to match other grid-info generators
  out <- tidyr::unnest(out, data)

  out
}

new_msgs_preprocessor <- function(i, n) {
  paste0("preprocessor ", i, "/", n)
}
new_msgs_model <- function(i, n, msgs_preprocessor) {
  paste0(msgs_preprocessor, ", model ", i, "/", n)
}

# c(1, 10) -> c("01", "10")
format_with_padding <- function(x) {
  gsub(" ", "0", format(x))
}

compute_config_ids <- function(data, id_preprocessor) {
  submodels <- unnest(data, .submodels, keep_empty = TRUE)
  submodels <- pull(submodels, .submodels)

  # Current model that actually is fit is not included in the submodel count
  # so we add 1
  model_sizes <- lengths(submodels) + 1L

  n_total_models <- sum(model_sizes)

  ids <- format_with_padding(seq_len(n_total_models))
  ids <- paste0(id_preprocessor, "_Model", ids)

  n_fit_models <- nrow(data)

  out <- vector("list", length = n_fit_models)

  start <- 1L

  for (i in seq_len(n_fit_models)) {
    size <- model_sizes[[i]]
    stop <- start + size - 1L
    out[[i]] <- ids[rlang::seq2(start, stop)]
    start <- stop + 1L
  }

  out
}

# ------------------------------------------------------------------------------

has_preprocessor <- function(workflow) {
  has_preprocessor_recipe(workflow) ||
    has_preprocessor_formula(workflow) ||
    has_preprocessor_variables(workflow)
}

has_preprocessor_recipe <- function(workflow) {
  "recipe" %in% names(workflow$pre$actions)
}

has_preprocessor_formula <- function(workflow) {
  "formula" %in% names(workflow$pre$actions)
}

has_preprocessor_variables <- function(workflow) {
  "variables" %in% names(workflow$pre$actions)
}

has_postprocessor <- function(workflow) {
  "tailor" %in% names(workflow$post$actions)
}

has_case_weights <- function(workflow) {
  "case_weights" %in% names(workflow$pre$actions)
}

has_spec <- function(workflow) {
  "model" %in% names(workflow$fit$actions)
}

set_workflow_spec <- function(workflow, spec) {
  workflow$fit$actions$model$spec <- spec
  workflow
}

set_workflow_recipe <- function(workflow, recipe) {
  workflow$pre$actions$recipe$recipe <- recipe
  workflow
}
