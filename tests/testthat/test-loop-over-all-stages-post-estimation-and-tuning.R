# These tests reference results generated by tune 1.3.0. The code to generate
# them (and the results) are found in the `inst` directory.

test_that("verifying loop_over_all_stages, no submodels, post estimation without tuning", {
  skip_if_not_installed("modeldata")
  skip_if_not_installed("kknn")
  skip_if_not_installed("probably")
  skip_if_not_installed("mgcv")

  load(system.file(
    "regression_tests",
    "simple_example.RData",
    package = "tune"
  ))

  # ------------------------------------------------------------------------------

  set.seed(1)
  dat <- modeldata::sim_regression(1000)
  rs <- vfold_cv(dat)

  rs_split <- rs$splits[[1]]
  rs_args <- rsample::.get_split_args(rs)

  rs_iter <- tune:::vec_list_rowwise(rs) |>
    purrr::pluck(1) |>
    mutate(
      .seeds = tune:::get_parallel_seeds(1)
    )

  # ------------------------------------------------------------------------------

  mod <- nearest_neighbor(neighbors = 11, weight_func = tune()) |>
    set_mode("regression")
  wflow <- workflow(outcome ~ ., mod, reg_cal_max)
  max_param <-
    wflow |>
    extract_parameter_set_dials() |>
    update(upper_limit = upper_limit(c(0, 1)))

  grd <- max_param |> grid_regular(levels = c(3, 2))
  upper_vals <- sort(unique(grd$upper_limit))

  static_1 <- tune:::make_static(
    wflow,
    param_info = max_param,
    grid = grd,
    metrics = metric_set(rmse, rsq),
    eval_time = NULL,
    split_args = rs_args,
    control = control_grid(save_pred = TRUE)
  )

  data_1 <- tune:::get_data_subsets(wflow, rs_split, rs_args)
  static_1 <- tune:::update_static(static_1, data_1)
  static_1$y_name <- "outcome"

  simple_res <- tune:::loop_over_all_stages(rs_iter, grd, static_1)
  expect_true(!is.null(simple_res$.metrics[[1]]))
  expect_named(
    simple_res,
    c(".metrics", ".notes", "outcome_names", "id", ".predictions")
  )
  expect_true(nrow(simple_res) == 1)
  expect_equal(
    nrow(simple_res$.predictions[[1]]),
    nrow(data_1$pred$data) * nrow(grd)
  )

  # TODO more tests can be added when calibration method = "none" is implemented
})

test_that("verifying loop_over_all_stages, submodels, post estimation without tuning", {
  skip_if_not_installed("modeldata")
  skip_if_not_installed("kknn")
  skip_if_not_installed("probably")
  skip_if_not_installed("mgcv")

  load(system.file(
    "regression_tests",
    "submodel_example.RData",
    package = "tune"
  ))

  # ------------------------------------------------------------------------------

  set.seed(1)
  dat <- modeldata::sim_regression(1000)
  rs <- vfold_cv(dat)

  rs_split <- rs$splits[[1]]
  rs_args <- rsample::.get_split_args(rs)

  rs_iter <- tune:::vec_list_rowwise(rs) |>
    purrr::pluck(1) |>
    mutate(
      .seeds = tune:::get_parallel_seeds(1)
    )

  # ------------------------------------------------------------------------------

  rec <- recipe(outcome ~ ., data = dat) |>
    step_pca(all_numeric_predictors(), num_comp = tune())

  mod <- nearest_neighbor(neighbors = tune("k"), weight_func = tune()) |>
    set_mode("regression")

  submodel_wflow <- workflow(rec, mod, reg_cal_max)
  max_param <-
    submodel_wflow |>
    extract_parameter_set_dials() |>
    update(upper_limit = upper_limit(c(0, 1)))

  upper_vals <- c(0, 1)

  # fmt: skip
  submodel_grid <-
    tibble::tribble(
      ~k,   ~weight_func, ~num_comp,
      9L,  "rectangular",        2L,
      14L,  "rectangular",        2L,
      20L,  "rectangular",        2L,
      4L,   "triangular",        2L,
      9L,   "triangular",        2L,
      14L,   "triangular",        2L,
      20L,   "triangular",        2L,
      4L, "epanechnikov",        2L,
      9L, "epanechnikov",        2L,
      14L, "epanechnikov",        2L,
      20L, "epanechnikov",        2L,
      4L,  "rectangular",       10L,
      9L,  "rectangular",       10L,
      14L,  "rectangular",       10L,
      20L,  "rectangular",       10L,
      4L,   "triangular",       10L,
      9L,   "triangular",       10L,
      14L,   "triangular",       10L,
      20L,   "triangular",       10L,
      4L, "epanechnikov",       10L,
      9L, "epanechnikov",       10L,
      14L, "epanechnikov",       10L,
      20L, "epanechnikov",       10L
    ) |>
    tidyr::crossing(upper_limit = upper_vals)

  # ------------------------------------------------------------------------------

  static_1 <- tune:::make_static(
    submodel_wflow,
    param_info = max_param,
    grid = submodel_grid,
    metrics = metric_set(rmse),
    eval_time = NULL,
    split_args = rs_args,
    control = tune::control_grid(save_pred = TRUE)
  )

  data_1 <- tune:::get_data_subsets(submodel_wflow, rs_split, rs_args)
  static_1 <- tune:::update_static(static_1, data_1)
  static_1$y_name <- "outcome"

  submodel_res <- tune:::loop_over_all_stages(rs_iter, submodel_grid, static_1)
  expect_true(!is.null(submodel_res$.metrics[[1]]))
  expect_named(
    submodel_res,
    c(".metrics", ".notes", "outcome_names", "id", ".predictions")
  )
  expect_true(nrow(submodel_res) == 1)
  expect_equal(
    nrow(submodel_res$.predictions[[1]]),
    nrow(data_1$pred$data) * nrow(submodel_grid)
  )
})

test_that("verifying loop_over_all_stages, submodels only, post estimation without tuning", {
  skip_if_not_installed("modeldata")
  skip_if_not_installed("kknn")
  skip_if_not_installed("probably")
  skip_if_not_installed("mgcv")

  load(system.file(
    "regression_tests",
    "submodel_only_example.RData",
    package = "tune"
  ))

  # ------------------------------------------------------------------------------

  set.seed(1)
  dat <- modeldata::sim_classification(1000)
  rs <- vfold_cv(dat)

  rs_split <- rs$splits[[1]]
  rs_args <- rsample::.get_split_args(rs)

  rs_iter <- tune:::vec_list_rowwise(rs) |>
    purrr::pluck(1) |>
    mutate(
      .seeds = tune:::get_parallel_seeds(1)
    )

  # ------------------------------------------------------------------------------

  mod <- nearest_neighbor(neighbors = tune(), weight_func = "triangular") |>
    set_mode("classification")

  submodel_only_wflow <- workflow(class ~ ., mod, cls_cal_tune_post)
  cut_vals <- c(.1, .9)
  submodel_only_grid <- tidyr::crossing(neighbors = 3:10, cut = cut_vals)

  # ------------------------------------------------------------------------------

  static_1 <- tune:::make_static(
    submodel_only_wflow,
    param_info = submodel_only_wflow |> extract_parameter_set_dials(),
    grid = submodel_only_grid,
    metrics = metric_set(accuracy, roc_auc, brier_class),
    eval_time = NULL,
    split_args = rs_args,
    control = tune::control_grid(save_pred = TRUE)
  )

  data_1 <- tune:::get_data_subsets(submodel_only_wflow, rs_split, rs_args)
  static_1 <- tune:::update_static(static_1, data_1)
  static_1$y_name <- "class"

  submodel_only_res <- tune:::loop_over_all_stages(
    rs_iter,
    submodel_only_grid,
    static_1
  )
  expect_true(!is.null(submodel_only_res$.metrics[[1]]))
  expect_named(
    submodel_only_res,
    c(".metrics", ".notes", "outcome_names", "id", ".predictions")
  )
  expect_true(nrow(submodel_only_res) == 1)
  expect_equal(
    nrow(submodel_only_res$.predictions[[1]]),
    nrow(data_1$pred$data) * nrow(submodel_only_grid)
  )

  # TODO more tests can be added when calibration method = "none" is implemented
})
