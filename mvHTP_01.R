# mvHTP.R
# Hard Thresholding Pursuit algorithm applied in MVMR individual data and binary outcome
# Select the valid IVs and estimate multiple treatments effects. 
#
# Usage: [Shat,Vhat,betahat,ci,betasd] = mvHTP(Y,D,Z,X,s,intercept,alpha,tuning,V,S)
#
# Y: Nx1 outcome vector
# D: Nxq treatment matrix
# Z: Nxpz candidate IVs
# X: Nxpx corvariates
# s: sparsity level
# intercept: whether or not introduce a intercept in linear regression
# alpha: confidence level
# tuning: parameter to adjust threshoulding level in first stage
# oracle: whether or not know the the true S and V
# V: true valid IVs
# S: true relevant IVs
# OutputRes: whether or not output the residuals of HTP.R
#
# Shat: estimated relevant IVs
# Vhat: estimated valid IVs
# betahat: estimated treatments effects
# ci: alpha-level confidence intervals for treatments effects
# betasd: standard deviation of estimated treatments effects
#


mvHTP_01 <- function(Y,D,Z,X,s,intercept=FALSE,alpha=0.05,tuning=30,OutputRes=TRUE,oracle=FALSE,V=NULL,S=NULL){
  # Check and Clean Input Type #
  # Check Y
  stopifnot(!missing(Y),(is.numeric(Y) || is.logical(Y)),(is.matrix(Y) || is.data.frame(Y)) && ncol(Y) == 1)
  stopifnot(all(!is.na(Y)))
  
  
  # Check D
  stopifnot(!missing(D),(is.numeric(D) || is.logical(D)),(is.matrix(D) || is.data.frame(D)) && ncol(D) >= 1)
  stopifnot(all(!is.na(D)))
  
  
  # Check Z
  stopifnot(!missing(Z),(is.numeric(Z) || is.logical(Z)),is.matrix(Z))
  stopifnot(all(!is.na(Z)))
  
  # Check dimesions
  stopifnot(length(Y) == nrow(D), length(Y) == nrow(Z))
  
  # Check s
  stopifnot(!missing(s),is.numeric(s) )
  
  # Check X, if present
  if(!missing(X) && !is.null(X)) {
    stopifnot((is.numeric(X) || is.logical(X)),is.matrix(X) && nrow(X) == nrow(Z))
    stopifnot(all(!is.na(X)))
    
    W = cbind(Z,X)
  } else {
    W = Z
    X = NULL
  }
  
  # All the other argument
  stopifnot(is.logical(intercept))
  stopifnot(is.numeric(alpha),length(alpha) == 1,alpha <= 1,alpha >= 0)
  stopifnot(is.numeric(tuning),length(tuning) == 1, tuning >=2)

  # Derive Inputs for TSHT
  n=length(Y)
  pz=ncol(Z)
  p=ncol(W)
  q=length(D)/n
  if(oracle==TRUE){
    stopifnot(!missing(S) && !missing(V))
    Vhat=V
    Shat=S
    
  }else{
    # Estimate Valid IVs
    SetHats = mvHTP.Vhat(Y,D,W,pz,s,intercept,OutputRes,tuning)
    Vhat = SetHats$Vhat
    Shat = SetHats$Shat
    
  }
  
  # Obtain 2SLS est, se, and ci
  Zs=Z[,Shat]
  W=cbind(Zs,X)
  X_=cbind(D,Zs[,-Vhat],X)
  auxreg <-lm.fit(W, D)
 Dhat = as.matrix(auxreg$fitted.values)
res= D-Dhat
 fit <- glm.fit(cbind(Dhat,W[,-Vhat],res),Y,family = binomial(link = "probit"))
  s2 <- sqrt(sum(fit$residuals^2)/fit$df.residual)
  betatilde = (fit$coefficients)[1:q]
  
  
  
  
  
  return(list(Shat=Shat, Vhat=Vhat, betahat=betatilde))
  
}

mvHTP.Vhat <- function(Y,D,W,pz,s,intercept=FALSE,OutputRes=TRUE,tuning=30) {
  # Include intercept
  if(intercept) {
    W = cbind(W,1)
  }
  p =  ncol(W) 
  n = length(Y)
  q = length(D)/n
  pj = p+q-1
  
  
  
  # CMLE of probit models
  stage1<-glm.fit(W[,1:pz],Y,family = binomial(link = "probit"))
  Gammahat = stage1$coefficients
  
  
  # ITT effects (OLS Estimation)
  gammatilde=gammahat=matrix(nrow =pz, ncol = q)
  deltahat=matrix(nrow = n,ncol = q)
  
  
  
  qrW = qr(W)
  for(j in 1:q){
    gammahat[,j]=qr.coef(qrW,D[,j])[1:pz]
    deltahat[,j]=qr.resid(qrW,D[,j])
  }
  
  
  # compute the covariance of W,delta(residual of D regress on Z)
  
  Sigmahat=1/(n-p)*t(W)%*%W
  Omegahat22=1/(n-q)*t(deltahat)%*%deltahat
  
  
  
  
  #==========threshold gamma===============
  
    thresh=sqrt(diag(solve(Sigmahat))[1:pz] %*% t(diag(Omegahat22)))*sqrt(tuning*log(n)/n)
    Sflag=(abs(gammahat)>thresh)
    gammatilde=Sflag*gammahat

  
  #========= estimate S* ==============
  Shat=which(apply(Sflag,1,sum)>0) #RESTRICT: ==0
  
  # Error check
  if(length(Shat) < q){
    warning("VHat Warning: No enough relevant IVs estimated. This may be due to weak IVs or identification condition not being met. Use more robust methods.")
    warning("Defaulting to all IVs being relevant","\n")
    Shat = 1:pz
  }
  
  #=========== estimate V* ===========
  if(s>length(Shat)-q){
    s=NULL
  }
  list = HTP(Gammahat[Shat],gammahat[Shat,],OutputRes)
  supp = (list$S)[-(1:q)]-q
  Vhat = Shat[-supp]
  
  # Error check
  if(length(Vhat) < q){
    warning("VHat Warning: No enough valid IVs estimated. This may be due to weak IVs or identification condition not being met. Use more robust methods.")
    warning("Defaulting to all relevant IVs being valid")
    Vhat = Shat
  }
  
  return(list(Vhat = Vhat,Shat=Shat))
  
}