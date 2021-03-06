#' Computing posterior probability of null hypotheses
#'
#' This function calculates the posterior probability of null hypotheses corresponding to each graph node.
#'
#' @param dataG1 Data for group1. \code{dataG1} need to be either a matrix or a 3-dimension array where the 1st dimension is the number of replicates. When \code{dataG1} is a matrix, it is called 'data of type vector' and the associated graph is a line graph. When \code{dataG1} is a 3-dimension array, it is called 'data of type matrix' and the associated graph is a lattice graph.
#' @param dataG2 Data for group2. Except for the 1st dimension, other dimensions of \code{dataG2} need to be the same as \code{dataG1}.
#' @param folder Path to folder that contains temporary files during the analysis. Default to be folder 'Scratch' within the working directory. This folder will be deleted when the analysis is completed. 
#' @param est_null Method for estimating prior probability of null hypothesis (\code{"qvalue"} or \code{"ashr"}) corresponding to usage of package \code{qvalue} or \code{ashr}, default to be \code{"ashr"}.
#' @param prior.null User-defined value for prior probability of null hypothesis. This value needs to be in (0,1). If this value is not provided, it is estimated using method specified by \code{est_null}. 
#' @param est_hyper Method for estimating hyperparameters (\code{"global"}, \code{"local"} or \code{"mixed"}). With method \code{"global"}, all the hyperparameters are estimated from the whole dataset. With method \code{"local"}, all the hyperparameters are estimated from each neighborhood. With method \code{"mixed"}, all the hyperparameters, except for the matrix parameter in Inverse-Wishart distribution,  are estimated from each neighborhood. Default value is \code{"mixed"}.
#' @param nbh_size Size of neighborhood considered in the analysis. This value is only used when data is of type vector and requires to be an odd number. The default value for this parameter is 5. When data is of type matrix, the size of neighborhood is always set to be 3.
#' @param mccores Number of cores to run in parallel.

#' @return Vector or matrix of posterior probability of null hypothesis.
#' @examples 
#' # See package vignettes
#' browseVignettes(package = "GraphMM")
#' @export

GraphMMcompute = function(dataG1, dataG2, folder="./Scratch", est_null = "ashr", prior.null = NULL,
                  est_hyper = "mixed", nbh_size = 5, mccores=1)
{
  if (!identical(dim(dataG1)[-1], dim(dataG2)[-1])) 
    stop('Error: data dimensions need to be the same for 2 groups. \n\n') 
  if (length(dim(dataG1)) == 2) {
      datatype = "vector"
  } else if (length(dim(dataG1)) == 3){
      datatype = "matrix" 
  } else {
    stop("Error: data need to be vector or matrix. \n\n")
  }
  if (!(est_hyper %in% c("global", "local", "mixed")))
  {
    stop("Error: method for estimating hyperparameters needs to be either global, local or mixed. \n")
  }
  if ((!is.null(prior.null)) && ((prior.null <= 0)||(prior.null >= 1)))
  {
    stop("Error: prior.null needs to be in (0,1). \n")
  }
  if (!(est_null %in% c("qvalue", "ashr")))
  {
    stop("Error: method for estimating prior null needs to be either qvalue or ashr. \n")
  }
  if ((nbh_size %% 2) == 0)
  {
    stop("Error: neighborhood size needs to be an odd number. \n")
  }
  if (nbh_size  < 3)
  {
    stop("Error: neighborhood size needs to be greater than or equal 3. \n")
  }
  if (nbh_size  > 11)
  {
    stop("Error: neighborhood size is too big and the analysis will be very slow. \n")
  }
  
  EEPostProb = GraphMM1(dataG1, dataG2, datatype, folder, est_null, prior.null,
                                est_hyper, nbh_size, mccores)
  return(EEPostProb)
}

GraphMM1 = function(dataG1, dataG2, datatype, folder, est_null, prior.null,
               est_hyper, nbh_size, mccores)
{
  if (datatype =="vector")
  {
    dat1.vec = dataG1
    dat2.vec = dataG2
    message(paste("Input data is of type vector. The corresponding graph is line graph \n",
                  "Number of vertices:  ", ncol(dat1.vec), "\n", "Computing ... \n", sep = ""))
  }

  if (datatype == "matrix")
  {
    size.im = dim(dataG1)[c(2,3)]
    IndicatorMatrix = matrix(1, size.im[1], size.im[2])
    IndicatorVector = c(IndicatorMatrix)
    IndexList = which(IndicatorMatrix==1,arr.ind=T)
    
    Nunits = dim(IndexList)[1]
    dat1.vec <- t(apply(dataG1, 1, c))
    dat2.vec <- t(apply(dataG2, 1, c))
    message(paste("Input data is of type matrix. The corresponding graph is lattice graph \n",
                  "Number of vertices:  ", ncol(dat1.vec), "\n", "Computing ... \n", sep = ""))
    
  }
  
  # Estimating prior null
  if (is.null(prior.null))
  {
    TtestList = lapply(1:dim(dat1.vec)[2], "ComputeTtest", dat1.vec, dat2.vec)
    teststat = rep(0, dim(dat1.vec)[2])
    pvalue = rep(0, dim(dat1.vec)[2])
    effect = rep(0, dim(dat1.vec)[2])
    effectsd = rep(0, dim(dat1.vec)[2])
    for (i in 1:dim(dat1.vec)[2])
    {
      effect[i] = TtestList[[i]]$effectsize
      effectsd[i] = TtestList[[i]]$effectsd
      teststat[i] = TtestList[[i]]$statistic
      pvalue[i] = TtestList[[i]]$p.value
    }
    
    if (est_null == "ashr") {
      res = ashr::ash(effect, effectsd, optmethod="mixEM")
      PriorNull = c(res$fitted_g$pi[1])
    } else {
      q = try(qvalue::qvalue(pvalue), silent = T)
      if (class(q) == "try-error") {
        message(paste("Warning: Cannot calculate q-values with error:", q[1], 
                      "See help on qvalue package for more details. \n",
                      "Instead, using package 'ashr' to estimate prior null probability", sep = ""))
        res = ashr::ash(effect, effectsd, optmethod="mixEM")
        PriorNull = c(res$fitted_g$pi[1])
      } else {
        PriorNull = c(q$pi0) 
      }
    }
  } else {
    PriorNull = prior.null
  }
  if (PriorNull < 10^-4) PriorNull = 0.0001
  if (PriorNull > (1-10^-4)) PriorNull = 0.9999
  
  ListPara=list()
  ListPara$PriorPara = c(PriorNull)
  
  # Estimating hyperparameters globally
  dat.mean1 = apply(dat1.vec,2,mean)
  dat.mean2 = apply(dat2.vec,2,mean)
  dat.sum = c(apply(dat1.vec,2,sum),apply(dat2.vec,2,sum))
  dat.sd1 = apply(dat1.vec,2,sd)
  dat.sd2 = apply(dat2.vec,2,sd)  
  
  ListPara$mu0 = mean(dat.mean1)
  ListPara$d0 = mean(dat.mean2 - dat.mean1)
  ListPara$tau = sd(dat.mean1)
  ListPara$delta = sd(dat.mean2 - dat.mean1)
  
  ListPara$deg = 2
  sample.cov.mat1 = cov(dat1.vec)
  sample.cov.mat2 = cov(dat2.vec)
  
  ListPara$mean.sd1 = mean(dat.sd1)
  ListPara$mean.sd2 = mean(dat.sd2)
  ListPara$mean.cor1 = mean(c(cov2cor(sample.cov.mat1)[upper.tri(sample.cov.mat1, diag = FALSE)]))
  ListPara$mean.cor2 = mean(c(cov2cor(sample.cov.mat2)[upper.tri(sample.cov.mat2, diag = FALSE)]))
  
  ListPara$PriorType = 4
  
  if (datatype =="vector")
  {
    Pspantree = unlist(pbmcapply::pbmclapply(1:dim(dat1.vec)[2], GetPostProb_vector, dat1.vec, dat2.vec, nbh_size, 
                                folder, est_hyper, ListPara, mc.cores = mccores))
  }
  if (datatype == "matrix")
  {
##    Pspantree1 = unlist(pbmcapply::pbmclapply(1:dim(IndexList)[1], GetPostProb_matrix, dat1.vec, dat2.vec,
##                               size.im, folder, est_hyper, ListPara, IndicatorVector, IndexList, mccores,
##                              mc.cores = 1))
##    Pspantree = matrix(Pspantree1, nrow = size.im[1], ncol = size.im[2])
##    Pspantree = matrix(Pspantree1, nrow = size.im[1], ncol = size.im[2])

    # just do central node of 3x3
    Pspantree1 =  GetPostProb_matrix(5, dat1.vec, dat2.vec,
                               size.im, folder, est_hyper, ListPara, IndicatorVector, IndexList, mccores)
                              
    Pspantree = Pspantree1
  }
  unlink(folder, recursive = T)
  return(Pspantree)
}

