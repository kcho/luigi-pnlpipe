## Guide for running tests

 * [Download Slicer](#download-slicer)
 * [Download test data](#download-test-data)
 * [Set up log directory](#set-up-log-directory)
 * [Launch container](#launch-container)
 * [Run tests](#run-tests)
 * [Local pull request](#local-pull-request)



### Download Slicer

* Download a fresh Slicer-4.11.20200930-linux-amd64 locally
* Install SlicerDMRI extension module. It can be found at `~/.config/NA-MIC/Extensions-29402/SlicerDMRI`
* You can copy both the Slicer-4.11.20200930-linux-amd64 and SlicerDMRI into `/root` directory 
for ease of mounting.


### Download test data

This step is intended for eliminating sluggishness involved in downloading test data from Dropbox repeatedly. 
You can have both `luigi-pnlpipe-test-data` and `luigi-pnlpipe-g-truth` downloaded in your machine. 
This approach is particularly useful when you would have to rebuild the Docker container. If you download them 
inside the container, then they would be lost during rebuild. But if they are downloaded locally once, 
you can mount them into your container after a rebuild.

* Test data

        d=luigi-pnlpipe-test-data.tar.gz
        # download locally
        wget https://www.dropbox.com/s/pzloevkr8h3kyac/$d
        # mount as
        docker run ... -v ~/$d:/home/pnlbwh/$d ...

* Ground truth

        r=luigi-pnlpipe-g-truth.tar.gz
        # download locally
        wget https://www.dropbox.com/s/gi7kukud44bl6p2/$r
        # mount as
        docker run ... -v ~/$r:/home/pnlbwh/luigi-pnlpipe/tests/$r ...


### Download IITmean_b0_256.nii.gz

    wget https://www.nitrc.org/frs/download.php/11290/IITmean_b0_256.nii.gz


### Set up log directory

* .gitconfig

Define the following `~/.gitconfig`:

```cfg
[color]
    ui = auto
[user]
    email = your_email
    name = your_name
```

* .ssh

Define the following `~/.ssh/config`:

```cfg
Host github.com
    IdentityFile ~/.ssh/your_private_key
    StrictHostKeyChecking no
```


* clone

Clone the private repo with SSH protocol:

> git clone git@github.com:pnlbwh/pnlpipe-nightly-tests.git

**NOTE** Users outside PNL will not have access to this repository. They can create a repository named `pnlpipe-nightly-tests` in 
their GitHub and adjust the above `pnlbwh/pnlpipe-nightly-tests.git` with their remote. In the simplest manner, just 
`mkdir pnlpipe-nightly-tests` and forget about `.gitconfig` or `.ssh`. If you do not set up a repository, you will not be able to 
upload the test logs to GitHub. Yet, you will be able to access them within `pnlpipe-nightly-tests` folder.

### Launch container


    docker run --rm -ti \
    # mount SlicerDMRI
    -v ~/Slicer-4.11.20200930-linux-amd64:/Slicer-4.11 \
    -v ~/SlicerDMRI:/SlicerDMRI \
    # mount FreeSurfer license
    -v ~/license.txt:/home/pnlbwh/freesurfer-7.1.0/license.txt \
    # mount IITmean_b0_256.nii.gz for CNN-Diffusion-MRIBrain-Segmentation
    -v ~/IITmean_b0_256.nii.gz:/home/pnlbwh/CNN-Diffusion-MRIBrain-Segmentation/model_folder/IITmean_b0_256.nii.gz \
    # mount .ssh, .gitconfig, pnlpipe-nightly-tests
    -v ~/.ssh:/root/.ssh \
    -v ~/.gitconfig:/home/pnlbwh/.gitconfig \
    -v ~/pnlpipe-nightly-tests:/home/pnlbwh/luigi-pnlpipe/pnlpipe-nightly-tests \
    tbillah/pnlpipe


### Run tests

    luigi-pnlpipe/pipeline_test.sh -h


### Local pull request

Let's say want to test the PR hcp<--provenance. Before merging on GitHub, we want to merge locally and test. Upon successful testing, 
we can merge the PR on GitHub. For this purpose, the following commands would come handy:

* PR when the local branch is hcp

        git reset --hard
        git pull origin hcp --ff-only
        git pull origin provenance --rebase


* PR when the local branch is not hcp

        git reset --hard
        git checkout --orphan hcp
        git rm -rf .
        git pull origin hcp --ff-only
        git pull origin azure --rebase


