% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/outcome-names.R
\name{outcome_names}
\alias{outcome_names}
\alias{outcome_names.terms}
\alias{outcome_names.formula}
\alias{outcome_names.recipe}
\alias{outcome_names.workflow}
\alias{outcome_names.tune_results}
\alias{outcome_names.workflow_variables}
\title{Determine names of the outcome data in a workflow}
\usage{
outcome_names(x, ...)

\method{outcome_names}{terms}(x, ...)

\method{outcome_names}{formula}(x, ...)

\method{outcome_names}{recipe}(x, ...)

\method{outcome_names}{workflow}(x, ...)

\method{outcome_names}{tune_results}(x, ...)

\method{outcome_names}{workflow_variables}(x, data = NULL, ...)
}
\arguments{
\item{x}{An object.}

\item{...}{Not used.}
}
\value{
A character string of variable names
}
\description{
Determine names of the outcome data in a workflow
}
\examples{
library(dplyr)
lm(cbind(mpg, wt) ~ ., data = mtcars) |>
  purrr::pluck(terms) |>
  outcome_names()
}
\keyword{internal}
