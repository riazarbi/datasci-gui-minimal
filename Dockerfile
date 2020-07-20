FROM riazarbi/datasci-python-minimal:latest

LABEL authors="Riaz Arbi,Gordon Inggs"

# Be explicit about user
# This is because we switch users during this build and it can get confusing
USER root

# ARGS =======================================================================

# Install R and RStudio
# Works
ENV RSTUDIO_VERSION 1.2.5001
# Doesn't work
#ENV RSTUDIO_VERSION 1.3.1056
ENV SHINY_VERSION 1.5.9.923

# Create same user as jupyter docker stacks so that k8s will run fine
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

# Configure environment
# Do we need this? Conflicts early locale settings
ENV SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    HOME=/home/$NB_USER

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
#    jupyter labextension install @jupyter-widgets/jupyterlab-manager && \
#    jupyter labextension install @jupyterlab/git && \
#    python3 -m pip install jupyterlab-git && \
#    jupyter serverextension enable --py jupyterlab_git --sys-prefix && \
#    python3 -m pip install ipyleaflet && \
#    jupyter nbextension enable --py --sys-prefix ipyleaflet && \
#    jupyter nbextension enable --py widgetsnbextension && \
#    jupyter labextension install jupyter-leaflet && \
#    python3 -m pip install ipympl && \
#    jupyter labextension install jupyter-matplotlib
 && chmod +x /usr/local/bin/fix-permissions \
# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
 && sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc \
# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
 && echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    chmod g+w /etc/passwd  \
 && /usr/local/bin/fix-permissions $HOME

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
 && wget --quiet https://download2.rstudio.org/server/bionic/amd64/rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
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
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
#   Note we use install2r because it halts build it package install fails. 
#   This is silent with install.packages(). Also multicore is nice.
 && Rscript -e 'install.packages(c("littler", "docopt"))' \ 
 && ln -s /usr/local/lib/R/site-library/littler/examples/install2.r /usr/local/bin/install2.r \
 && ln -s /usr/local/lib/R/site-library/littler/examples/installGithub.r /usr/local/bin/installGithub.r \
 && ln -s /usr/local/lib/R/site-library/littler/bin/r /usr/local/bin/r \
# Install jupyter R kernel
 && install2.r -e -n 3 -s --deps TRUE \
 devtools \
 shiny \ 
 rmarkdown \
 knitr \
 RJDBC \
# Jupyter-rsession
 && R -e "install.packages('IRkernel')" \
 && R --quiet -e "IRkernel::installspec(user=FALSE)" \
# && python3 -m pip install git+https://github.com/jupyterhub/jupyter-server-proxy \
# && python3 -m pip install git+https://github.com/jupyterhub/jupyter-rsession-proxy 
 && python3 -m pip install jupyter-server-proxy \
 && python3 -m pip install jupyter-rsession-proxy==1.2 
 
# USER SETTINGS ============================================================

# Switch to $NB_USER
USER $NB_UID
# Switch to $HOME of $NB_USER
WORKDIR $HOME

# Clean npm cache, create a new jupyter notebook config
RUN npm cache clean --force && \
    jupyter notebook --generate-config && \
    rm -rf /home/$NB_USER/.cache/yarn

# Configure container startup
CMD ["/bin/bash", "start-notebook.sh"]

# Add local files as late as possible to avoid cache busting
COPY start.sh /usr/local/bin/
COPY start-notebook.sh /usr/local/bin/
COPY start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root
RUN fix-permissions /etc/jupyter/
RUN fix-permissions $HOME

# Run as NB_USER ============================================================

USER $NB_USER
ENV PATH="${PATH}:/usr/lib/rstudio-server/bin"
