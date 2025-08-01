% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/last_fit.R
\name{last_fit}
\alias{last_fit}
\alias{last_fit.model_spec}
\alias{last_fit.workflow}
\title{Fit the final best model to the training set and evaluate the test set}
\usage{
last_fit(object, ...)

\method{last_fit}{model_spec}(
  object,
  preprocessor,
  split,
  ...,
  metrics = NULL,
  eval_time = NULL,
  control = control_last_fit(),
  add_validation_set = FALSE
)

\method{last_fit}{workflow}(
  object,
  split,
  ...,
  metrics = NULL,
  eval_time = NULL,
  control = control_last_fit(),
  add_validation_set = FALSE
)
}
\arguments{
\item{object}{A \code{parsnip} model specification or an unfitted
\link[workflows:workflow]{workflow()}. No tuning parameters are allowed; if arguments
have been marked with \link[hardhat:tune]{tune()}, their values must be
\link[=finalize_model]{finalized}.}

\item{...}{Currently unused.}

\item{preprocessor}{A traditional model formula or a recipe created using
\code{\link[recipes:recipe]{recipes::recipe()}}.}

\item{split}{An \code{rsplit} object created from \code{\link[rsample:initial_split]{rsample::initial_split()}} or
\code{\link[rsample:initial_validation_split]{rsample::initial_validation_split()}}.}

\item{metrics}{A \code{\link[yardstick:metric_set]{yardstick::metric_set()}}, or \code{NULL} to compute a standard
set of metrics.}

\item{eval_time}{A numeric vector of time points where dynamic event time
metrics should be computed (e.g. the time-dependent ROC curve, etc). The
values must be non-negative and should probably be no greater than the
largest event time in the training set (See Details below).}

\item{control}{A \code{\link[=control_last_fit]{control_last_fit()}} object used to fine tune the last fit
process.}

\item{add_validation_set}{For 3-way splits into training, validation, and test
set via \code{\link[rsample:initial_validation_split]{rsample::initial_validation_split()}}, should the validation set be
included in the data set used to train the model. If not, only the training
set is used.}
}
\value{
A single row tibble that emulates the structure of \code{fit_resamples()}.
However, a list column called \code{.workflow} is also attached with the fitted
model (and recipe, if any) that used the training set. Helper functions
for formatting tuning results like \code{\link[=collect_metrics]{collect_metrics()}} and
\code{\link[=collect_predictions]{collect_predictions()}} can be used with \code{last_fit()} output.
}
\description{
\code{\link[=last_fit]{last_fit()}} emulates the process where, after determining the best model,
the final fit on the entire training set is needed and is then evaluated on
the test set.
}
\details{
This function is intended to be used after fitting a \emph{variety of models}
and the final tuning parameters (if any) have been finalized. The next step
would be to fit using the entire training set and verify performance using
the test data.
}
\section{Case Weights}{

Some models can utilize case weights during training. tidymodels currently
supports two types of case weights: importance weights (doubles) and
frequency weights (integers). Frequency weights are used during model
fitting and evaluation, whereas importance weights are only used during
fitting.

To know if your model is capable of using case weights, create a model spec
and test it using \code{\link[parsnip:case_weights_allowed]{parsnip::case_weights_allowed()}}.

To use them, you will need a numeric column in your data set that has been
passed through either \code{\link[hardhat:importance_weights]{hardhat:: importance_weights()}} or
\code{\link[hardhat:frequency_weights]{hardhat::frequency_weights()}}.

For functions such as \code{\link[=fit_resamples]{fit_resamples()}} and the \verb{tune_*()} functions, the
model must be contained inside of a \code{\link[workflows:workflow]{workflows::workflow()}}. To declare that
case weights are used, invoke \code{\link[workflows:add_case_weights]{workflows::add_case_weights()}} with the
corresponding (unquoted) column name.

From there, the packages will appropriately handle the weights during model
fitting and (if appropriate) performance estimation.
}

\section{Censored Regression Models}{


Three types of metrics can be used to assess the quality of censored
regression models:
\itemize{
\item static: the prediction is independent of time.
\item dynamic: the prediction is a time-specific probability (e.g., survival
probability) and is measured at one or more particular times.
\item integrated: same as the dynamic metric but returns the integral of the
different metrics from each time point.
}

Which metrics are chosen by the user affects how many evaluation times
should be specified. For example:

\if{html}{\out{<div class="sourceCode">}}\preformatted{# Needs no `eval_time` value
metric_set(concordance_survival)

# Needs at least one `eval_time`
metric_set(brier_survival)
metric_set(brier_survival, concordance_survival)

# Needs at least two eval_time` values
metric_set(brier_survival_integrated, concordance_survival)
metric_set(brier_survival_integrated, concordance_survival)
metric_set(brier_survival_integrated, concordance_survival, brier_survival)
}\if{html}{\out{</div>}}

Values of \code{eval_time} should be less than the largest observed event
time in the training data. For many non-parametric models, the results beyond
the largest time corresponding to an event are constant (or \code{NA}).
}

\section{See also}{


\code{\link[=last_fit]{last_fit()}} is closely related to \code{\link[=fit_best]{fit_best()}}. They both
give you access to a workflow fitted on the training data but are situated
somewhat differently in the modeling workflow. \code{\link[=fit_best]{fit_best()}} picks up
after a tuning function like \code{\link[=tune_grid]{tune_grid()}} to take you from tuning results
to fitted workflow, ready for you to predict and assess further. \code{\link[=last_fit]{last_fit()}}
assumes you have made your choice of hyperparameters and finalized your
workflow to then take you from finalized workflow to fitted workflow and
further to performance assessment on the test data. While \code{\link[=fit_best]{fit_best()}} gives
a fitted workflow, \code{\link[=last_fit]{last_fit()}} gives you the performance results. If you
want the fitted workflow, you can extract it from the result of \code{\link[=last_fit]{last_fit()}}
via \link[=extract_workflow.tune_results]{extract_workflow()}.
}

\examples{
\dontshow{if (tune:::should_run_examples() & rlang::is_installed("splines2")) (if (getRversion() >= "3.4") withAutoprint else force)(\{ # examplesIf}
library(recipes)
library(rsample)
library(parsnip)

set.seed(6735)
tr_te_split <- initial_split(mtcars)

spline_rec <- recipe(mpg ~ ., data = mtcars) |>
  step_spline_natural(disp)

lin_mod <- linear_reg() |>
  set_engine("lm")

spline_res <- last_fit(lin_mod, spline_rec, split = tr_te_split)
spline_res

# test set metrics
collect_metrics(spline_res)

# test set predictions
collect_predictions(spline_res)

# or use a workflow

library(workflows)
spline_wfl <-
  workflow() |>
  add_recipe(spline_rec) |>
  add_model(lin_mod)

last_fit(spline_wfl, split = tr_te_split)
\dontshow{\}) # examplesIf}
}
