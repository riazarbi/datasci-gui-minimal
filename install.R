list.of.packages <- c("stringi",
			"devtools",
			"rmarkdown",  
			"knitr", 
			"RJDBC", 
			"reticulate",   
			"jsonlite", 
			"aws.s3",
                        "IRkernel",
                        "languageserver") 
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]


install.packages("remotes")

# use posit binary linux packages
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))
options(repos="https://packagemanager.rstudio.com/all/__linux__/focal/latest", Ncpus=3)
source("https://docs.posit.co/rspm/admin/check-user-agent.R")

if(length(new.packages)) install.packages(new.packages)

IRkernel::installspec(user=FALSE)
