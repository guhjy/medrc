#' 2-stage estimation in hierarchical dose-response models via meta-analysis
#' 
#' A two-stage meta-analysis approach to fit hierarchical dose-response models.
#' 
#' This function estimates population parameters from individual drm fits, using the metafor package.
#' 
#' @param formula a symbolic description of the model to be fit. Either of the form 'response \eqn{~} dose' or as a data frame with response values in first column and dose values in second column.
#' @param fct a list with three or more elements specifying the non-linear function, the accompanying self starter function, the names of the parameter in the non-linear function and, optionally, the first and second derivatives as well as information used for calculation of ED values. Currently available functions include, among others, the four- and five-parameter log-logistic models \code{\link{LL.4}}, \code{\link{LL.5}} and the Weibull model \code{\link{W1.4}}. Use \code{\link{getMeanFunctions}} for a full list.
#' @param ind a factor identifying individual curves.
#' @param data an optional data frame containing the variables in the model.
#' @param type a character string specifying the distribution of the data (parameter estimation will depend on the assumed distribution as different log likelihood functions will be used). 
#' The default is "continuous", corresponding to assuming a normal distribution. The choices "binary" and "event" imply a binomial and multinomial distribution, respectively. The choice "ssd" is for fitting a species sensitivity distribution.
#' @param cid2 a numeric vector or factor containing the between-curve grouping of the data.
#' @param pms2 a list containing a formula for each parameter in the nonlinear function.
#' @param struct correlation structure between population coefficients, either "CS" for compound symmetry, "HCS" for heteroscedastic compound symmetry, "UN" for an unstructured variance-covariance matrix, "ID" for a scaled identity matrix, "DIAG" for a diagonal matrix, "AR" for an AR(1) autoregressive structure, or "HAR" for a heteroscedastic AR(1) autoregressive structure.
#' @param method character string specifying whether the meta-analysis model should be fitted via maximum-likelihood ("ML") or via restricted maximum-likelihood ("REML") estimation. Default is "REML".
#' @param ... further arguments supplied to function drm.
#' 
#' @return An object of class 'metadrc'. 
#' 
#' @keywords models

metadrm <- function(formula, fct, ind, data, type="continuous", cid2=NULL, pms2=NULL, struct="UN", method="REML", ...){
  mf <- mfr <- call <- match.call(expand.dots = TRUE)
  nmf <- names(mf)
  mnmf <- c(1, match(c("formula", "curveid", "pmodels", "data", "fct", "subset", "na.action", "weights", "type", "bcVal", "bcAdd", "start", "robust", "logDose", "control", "lowerl", "upperl", "separate", "pshifts"), nmf, 0))
  mf <- mf[mnmf]
  mf[1] <- quote(drm())
  
  m <- match(c("formula", "data", "curveid", "ind", "cid2", "subset", "na.action", "weights"), names(mfr), 0L)
  mfr <- mfr[c(1L, m)]
  mfr$drop.unused.levels <- FALSE
  mfr[[1L]] <- quote(model.frame)
  mfr <- eval(mfr, parent.frame())
  id <- model.extract(mfr, "ind")
  cid <- model.extract(mfr, "curveid")
  gid <- model.extract(mfr, "cid2")
  
  if (!is.null(id)) id <-  droplevels(as.factor(id))
  if (!is.null(cid)) cid <-  droplevels(as.factor(cid))
  if (!is.null(gid)) gid <-  droplevels(as.factor(gid))
  
  ex <- levels(id)
  coefs <- vis <- NULL
  for (i in 1:length(ex)){
    subdata <- subset(data, id == ex[i])
    mf$data <- subdata
    mod <- eval(mf) 
    coefs <- rbind(coefs, coef(mod)) 
    vis <- rbind(vis, diag(vcov(mod)))
  }
  rownames(coefs) <- ex
  npar <- ncol(coefs)
  
  est <- data.frame(ind = as.factor(rep(ex, times=npar)),
                    coefficient=rep(names(coef(mod)), each=length(ex)),
                    estimate=as.vector(coefs),
                    variance=as.vector(vis))
  
  if (is.null(gid)){
    modsform <- ~ 0 + coefficient
  } else {
    grpname <- as.character(as.list(call)$cid2)
    gdat <- data.frame(id, gid)
    grplev <- unlist(lapply(split(gdat, id), function(spd){
      unique(spd[,"gid"])
    }))
    est[,grpname] <- as.factor(rep(grplev, times=npar))
    
    if (is.null(pms2)){
      modsform <- as.formula(paste("~ 0 + ", grpname, ":coefficient", sep=""))
    } else {
      Xc <- model.matrix(~ 0 + coefficient, data=est)
      Xlist <- lapply(1:ncol(Xc), function(i){
        Xp <- Xc[,i] * model.matrix(pms2[[i]], data=est)
        colnames(Xp) <- paste(fct$names[i], ":", colnames(Xp), sep="")
        return(Xp)
      })
      X <- Xlist[[1]]
      for (i in 2:length(Xlist)){
        X <- cbind(X, Xlist[[i]]) 
      }
      modsform <- as.formula(paste("~ 0 + X", sep=""))
    }
  }
  
  if (type == "continuous"){
    testarg <- "'t'" 
  } else {
    testarg <- "'z'"
  }
      
  res <- eval(parse(text=paste("rmadrc(estimate, V=variance, mods = modsform, random = ~ 0 + coefficient | ind, struct=struct, data=est, intercept=FALSE, method=method, test=", testarg,")", sep="")))
  
  rmacoef <- as.vector(res$beta)
  names(rmacoef) <- rownames(res$beta)
  
  parNames <- rownames(res$beta)
  if (length(mod$parNames[[1]]) == length(parNames)){
    names(rmacoef) <- names(mod$coefficients)
    parNames <- mod$parNames
  }
  
  out <- list(coefficients=rmacoef,
              vcov=res$vb,
              coefmat=coefs,
              varmat=vis, 
              estimates=est, 
              rma=res,
              data=data,
              fct=fct,
              call=call,
              type=mod$type)
  
  if (is.null(cid) & is.null(gid)){
    out$parmMat <- cbind(res$beta)
    out$parNames <- mod$parNames
    out$indexMat <- mod$indexMat
  } else {
    pmodels <- as.list(call)$pmodels
    if (is.null(pmodels) & is.null(pms2)){
      if (is.null(gid)){
        nc <- length(levels(cid))
        cnam <- levels(cid)
      }
      if (is.null(cid)){
        nc <- length(levels(gid))
        cnam <- levels(gid)
      }
      if (!is.null(cid) & !is.null(gid)){
        nc <- length(levels(cid))*length(levels(gid))
        cnam <- levels(interaction(cid, gid)) 
      }
      pmat <- matrix(rmacoef, ncol=nc, byrow=TRUE)
      colnames(pmat) <- cnam
      out$parmMat <- pmat
      out$indexMat <- matrix(1:length(rmacoef), ncol=nc, byrow=TRUE)
      out$parNames <- list(paste(rep(fct$names, each=nc), rep(cnam, times=length(fct$names)), sep=":"), rep(fct$names, each=nc), rep(cnam, times=length(fct$names)))
      names(out$coefficients) <- out$parNames[[1]]
    }
  }
  colnames(out$vcov) <- rownames(out$vcov) <- out$parNames[[1]]
  
  class(out) <- c("metadrc", "drc")
  return(out)
}