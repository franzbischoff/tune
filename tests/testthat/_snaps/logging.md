# low-level messages

    Code
      siren("a", "werewolf")
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "warning", "go", "danger", "success", "info"

---

    Code
      siren("bat", "info")
    Message
      i bat

---

    Code
      siren("bat", "go")
    Message
      > bat

---

    Code
      siren("bat", "danger")
    Message
      x bat

---

    Code
      siren("bat", "warning")
    Message
      ! bat

---

    Code
      siren("bat", "success")
    Message
      v bat

# update_printer

    Code
      update_printer(ctrl_t, rs, task = "cube", type = "go")
    Message
      > Fold01: cube
    Output
      NULL

---

    Code
      update_printer(ctrl_t, NULL, task = "cube", type = "go")
    Message
      > cube
    Output
      NULL

---

    Code
      update_printer(ctrl_t, rs, task = "cube", type = "success")
    Message
      v Fold01: cube
    Output
      NULL

# logging iterations

    Code
      log_best(ctrl_t, 10, sc_1)
    Message
      
      -- Iteration 10 ----------------------------------------------------------------
      
      i Current best:		0.8=7 (@iter 2)
    Output
      NULL

# logging search info

    Code
      check_and_log_flow(ctrl_t, mutate(tb_1, .mean = .mean * NA))
    Message
      x Skipping to next iteration
    Condition
      Error:
      ! no loop for break/next, jumping to top level

---

    Code
      check_and_log_flow(ctrl_t, slice(mutate(tb_1, .mean = .mean * NA), 1))
    Message
      x Halting search
    Condition
      Error:
      ! no loop for break/next, jumping to top level

# current results

    Code
      log_progress(ctrl_t, tb_2, maximize = FALSE, objective = "a")
    Message
      (x) Newest results:	a=4 (+/-0.4)

---

    Code
      log_progress(ctrl_t, tb_2, maximize = TRUE, objective = "b")
    Message
      <3 Newest results:	b=8 (+/-0.8)

---

    Code
      log_progress(ctrl_t, tb_2, maximize = TRUE, objective = "a")
    Message
      <3 Newest results:	a=4 (+/-0.4)

# show parameters

    Code
      param_msg(ctrl_t, iris[1, 4:5])
    Message
      i Petal.Width=0.2, Species=setosa

# acquisition functions

    Code
      acq_summarizer(ctrl_t, 1, conf_bound(I))
    Message
      i Kappa value: 1

---

    Code
      acq_summarizer(ctrl_t, 1, exp_improve(I))
    Message
      i Trade-off value: 1

---

    Code
      acq_summarizer(ctrl_t, 1, prob_improve(I))
    Message
      i Trade-off value: 1

# interactive logger works (fit_resamples, warning + error)

    Code
      res_fit <- fit_resamples(parsnip::nearest_neighbor("regression", "kknn"),
      Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(72, 40:45)], 5), control = control_resamples(
        extract = function(x) {
          raise_warning()
          raise_error()
        }, allow_par = FALSE))
    Message
      > A | warning: ope! yikes.
      > B | error:   AHHhH

---

    Code
      catalog_summary_test
    Output
      A: x5   B: x5

# interactive logger works (fit_resamples, rlang warning + error)

    Code
      res_fit <- fit_resamples(parsnip::nearest_neighbor("regression", "kknn"),
      Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(72, 40:45)], 5), control = control_resamples(
        extract = function(x) {
          raise_warning_rl()
          raise_error_rl()
        }, allow_par = FALSE))
    Message
      > A | warning: ope! yikes. (but rlang)
      > B | error:   AHHhH (but rlang)

---

    Code
      catalog_summary_test
    Output
      A: x5   B: x5

# interactive logger works (fit_resamples, multiline)

    Code
      res_fit <- fit_resamples(parsnip::nearest_neighbor("regression", "kknn"),
      Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(72, 40:45)], 5), control = control_resamples(
        extract = raise_multiline_conditions, allow_par = FALSE))
    Message
      > A | warning: hmmm what's happening
      > B | error:   aHHHksdjvndiuf

---

    Code
      catalog_summary_test
    Output
      A: x5   B: x5

# interactive logger works (fit_resamples, occasional error)

    Code
      res_fit <- fit_resamples(parsnip::nearest_neighbor("regression", "kknn"),
      Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(72, 40:45)], 5), control = control_resamples(
        extract = later, allow_par = FALSE))
    Message
      > A | error:   this errors now! ha!

---

    Code
      catalog_summary_test
    Output
      A: x2

# interactive logger works (fit_resamples, occasional errors)

    Code
      res_fit <- fit_resamples(parsnip::nearest_neighbor("regression", "kknn"),
      Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(72, 40:45)], 10),
      control = control_resamples(extract = function(x) {
        once()
        later()
      }, allow_par = FALSE))
    Message
      > A | error:   oh no
      > B | error:   this errors now! ha!

---

    Code
      catalog_summary_test
    Output
      A: x1   B: x6

# interactive logger works (fit_resamples, many distinct errors)

    Code
      res_fit <- fit_resamples(parsnip::nearest_neighbor("regression", "kknn"),
      Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(72, 40:45)], 5), control = control_resamples(
        extract = numbered, allow_par = FALSE))
    Message
      > A | error:   error number 1
      > B | error:   error number 2
      > C | error:   error number 3
      > D | error:   error number 4
      > E | error:   error number 5

---

    Code
      catalog_summary_test
    Output
      A: x1   B: x1   C: x1   D: x1   E: x1

# interactive logger works (tune grid, error)

    Code
      res_fit <- tune_grid(parsnip::nearest_neighbor("regression", "kknn",
        dist_power = tune()), Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(
        72, 40:45)], 5), grid = 5, control = control_grid(extract = raise_error,
        allow_par = FALSE))
    Message
      > A | error:   AHHhH

---

    Code
      catalog_summary_test
    Output
      A: x75

# interactive logger works (bayesian, error)

    Code
      res_grid <- tune_bayes(parsnip::nearest_neighbor("regression", "kknn",
        dist_power = tune()), Sale_Price ~ ., rsample::vfold_cv(modeldata::ames[, c(
        72, 40:45)], 5), initial = 5, iter = 5, control = control_bayes(extract = raise_error,
        allow_par = FALSE))
    Message
      > A | error:   AHHhH

---

    Code
      catalog_summary_test
    Output
      A: x100

