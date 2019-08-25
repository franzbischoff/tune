library(tidymodels)
library(workflows)
library(tune)
library(caret)

data("segmentationData")

theme_set(theme_bw())

# ------------------------------------------------------------------------------

segmentationData <-
  segmentationData %>%
  dplyr::select(-Case, -Cell, -contains("Centroid"))

set.seed(8567)
tr_te_split <- initial_split(segmentationData)

seg_train <- training(tr_te_split)
seg_test  <-  testing(tr_te_split)

folds <- vfold_cv(seg_train)

# ------------------------------------------------------------------------------

seg_pre_proc <-
  recipe(Class ~ ., data = seg_train) %>%
  step_YeoJohnson(all_predictors()) %>%
  step_normalize(all_predictors()) %>%
  step_pca(all_predictors(), num_comp = tune()) %>%
  step_downsample(Class)

svm_mod <-
  svm_rbf(mode = "classification", cost = tune(), rbf_sigma = tune()) %>%
  set_engine("kernlab")

svm_wflow <-
  workflow() %>%
  add_model(svm_mod) %>%
  add_recipe(seg_pre_proc)

# ------------------------------------------------------------------------------

svm_set <-
  svm_wflow %>%
  param_set() %>%
  update("num_comp", num_comp(c(1, 20)))

set.seed(1558)
grid <- grid_max_entropy(svm_set, size = 5)

grid_results <- tune_grid(svm_wflow, rs = folds, grid = grid,
                          control = grid_control(verbose = TRUE))

grid_results

grid_results$.metrics[[1]]

estimate(grid_results)

# functions to pick best or other rules

# ------------------------------------------------------------------------------

kappa_only <- metric_set(kap)

svm_search <- tune_Bayes(svm_wflow, rs = folds,
                         initial = grid_results,
                         iter = 10,
                         perf = kappa_only,
                         param_info = svm_set,
                         control = Bayes_control(verbose = TRUE))

plot_perf_vs_iter(svm_search, "kap")

# ------------------------------------------------------------------------------

svm_search_2 <- tune_Bayes(svm_wflow, rs = folds,
                           initial = svm_search,
                           iter = 10,
                           perf = kappa_only,
                           param_info = svm_set,
                           control = Bayes_control(verbose = TRUE))

plot_perf_vs_iter(svm_search_2, "kap")


svm_search_2 %>% dplyr::filter(.iter > 0) %>%
  ggplot(aes(x = cost, y = rbf_sigma)) +
  geom_path(aes(x = cost, y = rbf_sigma), col = "black") +
  geom_point(aes(col = num_comp, size = mean))  +
  geom_point(data = svm_search_2, aes(col = num_comp, size = mean), pch = 1) +
  scale_x_log10() +
  scale_y_log10()

svm_search_2 %>%
  dplyr::filter(.metric == "kap") %>%
  dplyr::select(-.estimator, -.metric, -n, -std_err) %>%
  mutate(cost = log10(cost), rbf_sigma = log10(rbf_sigma)) %>%
  gather(variable, value, -mean, -.iter) %>%
  ggplot(aes(x = .iter, y = value)) +
  geom_point() +
  facet_wrap(~ variable, scales = "free_y")


svm_search_2 %>%
  dplyr::filter(.metric == "kap") %>%
  dplyr::select(-.estimator, -.metric, -n, -std_err) %>%
  mutate(cost = log10(cost), rbf_sigma = log10(rbf_sigma)) %>%
  gather(variable, value, -mean, -.iter) %>%
  ggplot(aes(x = value, y = mean)) +
  geom_point() +
  facet_wrap(~ variable, scales = "free_x")

