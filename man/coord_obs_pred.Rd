% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/coord_obs_pred.R
\name{coord_obs_pred}
\alias{coord_obs_pred}
\title{Use same scale for plots of observed vs predicted values}
\usage{
coord_obs_pred(ratio = 1, xlim = NULL, ylim = NULL, expand = TRUE, clip = "on")
}
\arguments{
\item{ratio}{Aspect ratio, expressed as \code{y / x}. Defaults to 1.0.}

\item{xlim, ylim}{Limits for the x and y axes.}

\item{expand}{Not currently used.}

\item{clip}{Should drawing be clipped to the extent of the plot panel? A setting
of "on" (the default) means yes, and a setting of "off" means no. In most
cases, the default of "on" should not be changed, as setting \code{clip = "off"}
can cause unexpected results. It allows drawing of data points anywhere on
the plot, including in the plot margins. If limits are set via \code{xlim} and
\code{ylim} and some data points fall outside those limits, then those data points
may show up in places such as the axes, the legend, the plot title, or the
plot margins.}
}
\value{
A \code{ggproto} object.
}
\description{
For regression models, \code{coord_obs_pred()} can be used in a ggplot to make the
x- and y-axes have the same exact scale along with an aspect ratio of one.
}
\examples{
\dontshow{if (rlang::is_installed("modeldata")) (if (getRversion() >= "3.4") withAutoprint else force)(\{ # examplesIf}
# example code
data(solubility_test, package = "modeldata")

library(ggplot2)
p <- ggplot(solubility_test, aes(x = solubility, y = prediction)) +
  geom_abline(lty = 2) +
  geom_point(alpha = 0.5)

p

p + coord_fixed()

p + coord_obs_pred()
\dontshow{\}) # examplesIf}
}
