FROM riazarbi/datasci-base:20210626122810

LABEL authors="Riaz Arbi,Gordon Inggs"

# Be explicit about user
# This is because we switch users during this build and it can get confusing
USER root

# ARGS =======================================================================

# Install R and RStudio
# Works
ENV RSTUDIO_VERSION=1.4.1722
#https://s3.amazonaws.com/rstudio-ide-build/server/bionic/amd64/rstudio-server-1.4.1722-amd64.deb
ENV SHINY_VERSION=1.5.9.923
ENV RSESSION_PROXY_RSTUDIO_1_4=yes
#ENV RSESSION_PROXY_WWW_ROOT_PATH='/rstudio/'

# Create same user as jupyter docker stacks so that k8s will run fine
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

# Configure environment
# Do we need this? Conflicts early locale settings
ENV SHELL=/bin/bash 
ENV NB_USER=$NB_USER
ENV NB_UID=$NB_UID 
ENV NB_GID=$NB_GID 
ENV LC_ALL=en_US.UTF-8 
ENV LANG=en_US.UTF-8 
ENV LANGUAGE=en_US.UTF-8 
ENV TZ="Africa/Johannesburg" 
ENV HOME=/home/$NB_USER 
ENV JUPYTER_ENABLE_LAB=1 
ENV R_LIBS_SITE=/usr/lib/R/site-library

# JUPYTER =====================================================================

# Expose the right port
EXPOSE 8888

# Add a script that we will use to correct permissions after running certain commands
ADD fix-permissions /usr/local/bin/fix-permissions 

RUN DEBIAN_FRONTEND=noninteractive \ 
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -yq --no-install-recommends \
    npm nodejs \
# Install all the jupyter packages
 && python3 -m pip install --upgrade pip && \
    python3 -m pip install jupyter jupyterhub jupyterlab \
 && python3 -m pip install nbgitpuller \
 && chmod +x /usr/local/bin/fix-permissions \
# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
 && sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc \
# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
 && echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    usermod -a -G staff $NB_USER && \
    chmod g+w /etc/passwd  \
 && /usr/local/bin/fix-permissions $HOME \
 && rm -rf /tmp/*

# RSESSION ==================================================================

# Add apt gpg key
RUN gpg --keyserver keyserver.ubuntu.com --recv-key E298A3A825C0D65DFD57CBB651716619E084DAB9 \
 && gpg -a --export E298A3A825C0D65DFD57CBB651716619E084DAB9 | sudo apt-key add - \
 && echo deb https://cloud.r-project.org/bin/linux/ubuntu focal-cran40/ >> /etc/apt/sources.list \
 && echo deb http://za.archive.ubuntu.com/ubuntu/ focal-backports main restricted universe >> /etc/apt/sources.list \
# Install prerequisites
 && DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    fonts-dejavu \
    gfortran \
    libclang-dev \
    r-base \
    r-recommended \
    r-base-dev \
    gdebi-core \
# Install RStudio
 #&& wget --quiet https://download2.rstudio.org/server/bionic/amd64/rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
 && wget --quiet https://s3.amazonaws.com/rstudio-ide-build/server/bionic/amd64/rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
 && gdebi -n rstudio-server-${RSTUDIO_VERSION}-amd64.deb \ 
 && rm rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
# Install Shiny Server
 && wget -q "https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-${SHINY_VERSION}-amd64.deb" -O ss-latest.deb \
 && gdebi -n ss-latest.deb \
 && rm -f ss-latest.deb \
#    Install R package dependencies
 && DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    libxml2-dev \
    libssh2-1-dev \
    libgit2-dev \
    libcurl4-openssl-dev \
    cargo \
    libmagick++-dev \
    libfontconfig1-dev \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* 
#   Note we use install2r because it halts build it package install fails. 
#   This is silent with install.packages(). Also multicore is nice.
RUN Rscript -e 'install.packages(c("littler", "docopt"))' \ 
 && ln -s /usr/lib/R/site-library/littler/examples/install2.r /usr/local/bin/install2.r \
 && ln -s /usr/lib/R/site-library/littler/examples/installGithub.r /usr/local/bin/installGithub.r \
 && ln -s /usr/lib/R/site-library/littler/bin/r /usr/local/bin/r \
# Set up openblas and link to R
 && install2.r --skipinstalled --error  --ncpus 3 --deps TRUE -l $R_LIBS_SITE  \   
    ropenblas \
 && R -e "ropenblas::ropenblas()" \
 && rm -rf /tmp/*

# Install jupyter R kernel
RUN install2.r --skipinstalled --error  --ncpus 3 --deps TRUE -l $R_LIBS_SITE   \
    devtools \
    shiny \ 
    rmarkdown \
    knitr \
    RJDBC \
    reticulate \
    jsonlite \
 && R -e "install.packages('IRkernel')" \
 && R --quiet -e "IRkernel::installspec(user=FALSE)" \
 #&& python3 -m pip install jupyter-server-proxy \
 && python3 -m pip install git+https://github.com/zeehio/jupyter-server-proxy.git@03afb8b6816d0cf51af34bb995d6da078aac6185 \
 #&& python3 -m pip install jupyter-rsession-proxy==1.2 
 && python3 -m pip install git+https://github.com/zeehio/jupyter-rsession-proxy.git@9def6461460e3b43df7db718c3276504d4252873 \
# Fix revocaiton list permissions for rserver
 && echo "auth-revocation-list-dir=/tmp/rstudio-server-revocation-list/" >> /etc/rstudio/rserver.conf \
 && rm -rf /tmp/*

# JULIA ====================================================================

# Julia dependencies
# install Julia packages in /opt/julia instead of $HOME
ENV JULIA_DEPOT_PATH=/opt/julia
ENV JULIA_PKGDIR=/opt/julia
ENV JULIA_VERSION=1.5.0

WORKDIR /tmp

# hadolint ignore=SC2046
RUN mkdir "/opt/julia-${JULIA_VERSION}" && \
    wget -q https://julialang-s3.julialang.org/bin/linux/x64/$(echo "${JULIA_VERSION}" | cut -d. -f 1,2)"/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" && \
    #echo "fd6d8cadaed678174c3caefb92207a3b0e8da9f926af6703fb4d1e4e4f50610a *julia-${JULIA_VERSION}-linux-x86_64.tar.gz" | sha256sum -c - && \
    tar xzf "julia-${JULIA_VERSION}-linux-x86_64.tar.gz" -C "/opt/julia-${JULIA_VERSION}" --strip-components=1 && \
    rm "/tmp/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
 && ln -fs /opt/julia-*/bin/julia /usr/local/bin/julia \
# Show Julia where conda libraries are \
 && mkdir /etc/julia  \
# Create JULIA_PKGDIR 
 && mkdir "${JULIA_PKGDIR}"  \
 && chown "${NB_USER}" "${JULIA_PKGDIR}" \
    /usr/local/bin/fix-permissions "${JULIA_PKGDIR}" \ 
# Install IJulia as jovyan and then move the kernelspec out
# to the system share location. Avoids problems with runtime UID change not
# taking effect properly on the .local folder in the jovyan home dir.
 && julia -e 'import Pkg; Pkg.update()'  \
 &&  julia -e "using Pkg; pkg\"add IJulia\"; pkg\"precompile\"" \
    # move kernelspec out
 && mv "${HOME}/.local/share/jupyter/kernels/julia"* "/usr/local/share/jupyter/kernels/"  \
 && chmod -R go+rx "/usr/local/share/jupyter"  \
 && rm -rf "${HOME}/.local"  \
 && /usr/local/bin/fix-permissions "${JULIA_PKGDIR}" "/usr/local/share/jupyter" \
 && rm -rf /tmp/*

# USER SETTINGS ============================================================

# Switch to $NB_USER
USER $NB_UID

# Switch to $HOME of $NB_USER
WORKDIR $HOME

# Set NB_USER ENV vars
ENV PATH="${PATH}:/usr/lib/rstudio-server/bin" 
ENV TZ="Africa/Johannesburg"

# Clean npm cache, create a new jupyter notebook config
RUN npm cache clean --force  \
 && jupyter notebook --generate-config  \
 && rm -rf /home/$NB_USER/.cache/yarn 

# Configure container startup
CMD ["/bin/bash", "start-notebook.sh"]

# Add local files as late as possible to avoid cache busting
COPY start.sh /usr/local/bin/
COPY start-notebook.sh /usr/local/bin/
COPY start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root
RUN /usr/local/bin/fix-permissions /etc/jupyter/
RUN /usr/local/bin/fix-permissions $HOME ${JULIA_PKGDIR}

# Run as NB_USER ============================================================

USER $NB_USER
