#' @title Summary of Bayesian multivariate-response mediation-models
#' @name mediation
#'
#' @description \code{mediation()} is a short summary for multivariate-response
#'   mediation-models.
#'
#' @param x A \code{stanreg}, \code{stanfit}, or \code{brmsfit} object.
#' @param prob Vector of scalars between 0 and 1, indicating the mass within
#'   the credible interval that is to be estimated.
#' @param treatment Character, name of the treatment variable (or direct effect)
#'   in a (multivariate response) mediator-model. If missing, \code{mediation()}
#'   tries to find the treatment variable automatically, however, this may fail.
#' @param mediator Character, name of the mediator variable in a (multivariate
#'   response) mediator-model. If missing, \code{mediation()} tries to find the
#'   treatment variable automatically, however, this may fail.
#' @param typical The typical value that will represent the Bayesian point estimate.
#'   By default, the posterior median is returned. See \code{\link[sjmisc]{typical_value}}
#'   for possible values for this argument.
#' @param ... Not used.
#'
#' @return A data frame with direct, indirect, mediator and
#'   total effect of a multivariate-response mediation-model, as well as the
#'   proportion mediated. The effect sizes are mean values of the posterior
#'   samples.
#'
#' @details \code{mediation()} returns a data frame with information on the
#'       \emph{direct effect} (mean value of posterior samples from \code{treatment}
#'       of the outcome model), \emph{mediator effect} (mean value of posterior
#'       samples from \code{mediator} of the outcome model), \emph{indirect effect}
#'       (mean value of the multiplication of the posterior samples from
#'       \code{mediator} of the outcome model and the posterior samples from
#'       \code{treatment} of the mediation model) and the total effect (mean
#'       value of sums of posterior samples used for the direct and indirect
#'       effect). The \emph{proportion mediated} is the indirect effect divided
#'       by the total effect.
#'       \cr \cr
#'       For all values, the 90\% HDIs are calculated by default. Use \code{prob}
#'       to calculate a different interval.
#'       \cr \cr
#'       The arguments \code{treatment} and \code{mediator} do not necessarily
#'       need to be specified. If missing, \code{mediation()} tries to find the
#'       treatment and mediator variable automatically. If this does not work,
#'       specify these variables.
#'
#'
#' @export
mediation <- function(x, ...) {
  UseMethod("mediation")
}


#' @rdname mediation
#' @importFrom purrr map
#' @importFrom stats formula
#' @importFrom dplyr pull bind_cols
#' @importFrom sjmisc typical_value
#' @importFrom insight model_info
#' @importFrom bayestestR hdi
#' @export
mediation.brmsfit <- function(x, treatment, mediator, prob = .9, typical = "median", ...) {
  # check for pkg availability, else function might fail
  if (!requireNamespace("brms", quietly = TRUE))
    stop("Please install and load package `brms` first.")

  # only one HDI interval
  if (length(prob) > 1) prob <- prob[1]

  # check for binary response. In this case, user should rescale variables
  fitinfo <- insight::model_info(x)
  if (any(purrr::map_lgl(fitinfo, ~ .x$is_bin))) {
    message("One of moderator or outcome is binary, so direct and indirect effects may be on different scales. Consider rescaling model predictors, e.g. with `sjmisc::std()`.")
  }


  dv <- insight::find_response(x, combine = TRUE)
  fixm <- FALSE

  if (missing(mediator)) {
    pv <- insight::find_predictors(x, flatten = TRUE)
    mediator <- pv[pv %in% dv]
    fixm <- TRUE
  }

  if (missing(treatment)) {
    pvs <- purrr::map(
      x$formula$forms,
      ~ stats::formula(.x)[[3L]] %>% all.vars()
    )

    treatment <- pvs[[1]][pvs[[1]] %in% pvs[[2]]][1]
    treatment <- fix_factor_name(x, treatment)
  }


  mediator.model <- which(dv == mediator)
  treatment.model <- which(dv != mediator)

  if (fixm) mediator <- fix_factor_name(x, mediator)

  # brms removes underscores from variable names when naming estimates
  # so we need to fix variable names here

  dv <- names(dv)


  # Direct effect: coef(treatment) from model_y_treatment
  coef_treatment <- sprintf("b_%s_%s", dv[treatment.model], treatment)
  eff.direct <- x %>%
    brms::posterior_samples(pars = coef_treatment, exact_match = TRUE) %>%
    dplyr::pull(1)

  # Mediator effect: coef(mediator) from model_y_treatment
  coef_mediator <- sprintf("b_%s_%s", dv[treatment.model], mediator)
  eff.mediator <- x %>%
    brms::posterior_samples(pars = coef_mediator, exact_match = TRUE) %>%
    dplyr::pull(1)

  # Indirect effect: coef(treament) from model_m_mediator * coef(mediator) from model_y_treatment
  coef_indirect <- sprintf("b_%s_%s", dv[mediator.model], treatment)
  tmp.indirect <- brms::posterior_samples(x, pars = c(coef_indirect, coef_mediator), exact_match = TRUE)
  eff.indirect <- tmp.indirect[[coef_indirect]] * tmp.indirect[[coef_mediator]]

  # Total effect
  eff.total <- eff.indirect + eff.direct

  # proportion mediated: indirect effect / total effect
  prop.mediated <- sjmisc::typical_value(eff.indirect, fun = typical) / sjmisc::typical_value(eff.total, fun = typical)
  hdi_eff <- bayestestR::hdi(eff.indirect / eff.total, ci = prob)
  prop.se <- (hdi_eff$CI_high - hdi_eff$CI_low) / 2
  prop.hdi <- prop.mediated + c(-1, 1) * prop.se

  res <- data_frame(
    effect = c("direct", "indirect", "mediator", "total", "proportion mediated"),
    value = c(
      sjmisc::typical_value(eff.direct, fun = typical),
      sjmisc::typical_value(eff.indirect, fun = typical),
      sjmisc::typical_value(eff.mediator, fun = typical),
      sjmisc::typical_value(eff.total, fun = typical),
      prop.mediated
    )
  ) %>% dplyr::bind_cols(
    as.data.frame(rbind(
      bayestestR::hdi(eff.direct, ci = prob)[, -1],
      bayestestR::hdi(eff.indirect, ci = prob)[, -1],
      bayestestR::hdi(eff.mediator, ci = prob)[, -1],
      bayestestR::hdi(eff.total, ci = prob)[, -1],
      prop.hdi
    ))
  )

  colnames(res) <- c("effect", "value", "hdi.low", "hdi.high")

  attr(res, "prob") <- prob
  attr(res, "treatment") <- treatment
  attr(res, "mediator") <- mediator
  attr(res, "response") <- dv[treatment.model]
  attr(res, "formulas") <- lapply(x$formula$forms, function(x) as.character(x[1]))

  class(res) <- c("sj_mediation", class(res))
  res
}


#' @importFrom insight get_data
fix_factor_name <- function(model, variable) {
  # check for categorical. if user has not specified a treatment variable
  # and this variable is categorical, the posterior samples contain the
  # samples from each category of the treatment variable - so we need to
  # fix the variable name

  mf <- insight::get_data(model)
  if (obj_has_name(mf, variable)) {
    check_fac <- mf[[variable]]
    if (is.factor(check_fac)) {
      variable <- sprintf("%s%s", variable, levels(check_fac)[nlevels(check_fac)])
    } else if (is.logical(check_fac)) {
      variable <- sprintf("%sTRUE", variable)
    }
  }

  variable
}
