#!/usr/bin/bash

usage () {
echo -e "
Convenient script for testing luigi-pnlpipe, pnlNipype, 
CNN-Diffusion-MRIBrain-Segmentation, and pnlpipe_software

Usage:
./pipeline_test.sh [--no-clone] [--no-remove] [--hack-fs] [--pytest-only] [--console-print]
                   [--luigi-pnlpipe BRANCH_NAME] [--pnlNipype BRANCH_NAME] [--to RECIPIENTS]

The default branches are the ones at https://github.com/pnlbwh/luigi-pnlpipe
and https://github.com/pnlbwh/pnlNipype.
Specify email recipients of the domain @bwh.harvard.edu within double quotes e.g.
--to \"sbouix tbillah kcho\"
"

exit 0
}


OPTS=`getopt -l help,no-clone,no-remove,hack-fs,pytest-only,console-print,branch:,to: \
-o h,c,r,f,o,p,b:,t: -- "$@"`
eval set -- "$OPTS"


while true
do
    case "$1" in
        -h|--help)
            usage;;
        --no-clone)
            noclone=1;
            shift 1;;
        --no-remove)
            noremove=1;
            shift 1;;
        --hack-fs)
            hackfs=1;
            shift 1;;
        --pytest-only)
            pytest_only=1;
            shift 1;;
        --console-print)
            console_print=1;
            shift 1;;
        --luigi-pnlpipe)
            luigi_branch=$2;
            shift 2;;
        --pnlNipype)
            nipype_branch=$2;
            shift 2;;
        --to)
            to=$2;
            shift 2;;
        --) 
            shift;
            break;;
        *)  
            echo One or more of the args could not be recognized
            echo See ./pipeline_test.sh --help
            exit 1
    esac
done


cd /home/pnlbwh


# do not clone again
if [[ -z $noclone ]]
then
    cd luigi-pnlpipe
    git reset --hard
    git pull origin $luigi_branch

    cd ../pnlNipype
    git pull origin $nipype_branch

    cd ..
fi


# do not remove any previous output
remove=1
if [[ ! -z $noremove ]]
then
    echo Not removing any previous output
    remove=0
fi



# download test data
test_data=luigi-pnlpipe-test-data.tar.gz
if [ ! -f $test_data ]
then
    wget https://www.dropbox.com/s/pzloevkr8h3kyac/$test_data
fi

if [ ! -d CTE/rawdata ] || [ ! -d HCP/rawdata ]
then

    tar -xzvf $test_data


    # download and shorten T2w test data
    if [ ! -d trainingDataT2Masks ]
    then
        git clone https://github.com/pnlbwh/trainingDataT2Masks.git
        pushd .
        cd trainingDataT2Masks
        ./mktrainingcsv.sh .

        head -n 5 trainingDataT2Masks-hdr.csv > trainingDataT2Masks-curt.csv
        popd
    fi
fi


# hack recon-all
if [[ ! -z $hackfs ]]
then
    sed -i "361s+cmd+'mv $HOME/CTE/rawdata/freesurfer $HOME/CTE/derivatives/pnlpipe/sub-1004/ses-01/anat/'+g" \
    luigi-pnlpipe/workflows/struct_pipe.py
fi



export ANTS_RANDOM_SEED=123456

cd luigi-pnlpipe

# create test log directory
datestamp=$(date +"%Y-%m-%d")
log=logs-$datestamp
mkdir -p $log



if [[ -z $pytest_only ]]
then


### HCP ###

## dwi pipeline ##
export LUIGI_CONFIG_PATH=`pwd`/test_params/dwi_pipe_params.cfg

# test of EddyEpi (TopupEddy) and Ukf
# replace eddy_epi_task, acqp, index in dwi_pipe_params
sed -i "s/eddy_epi_task:\ EddyEpi/eddy_epi_task:\ topupeddy/g" test_params/dwi_pipe_params.cfg
sed -i "s/acqp.txt/acqp_ap_pa.txt/g" test_params/dwi_pipe_params.cfg
sed -i "s+/home/pnlbwh/luigi-pnlpipe/test_params/index.txt++g" test_params/dwi_pipe_params.cfg

workflows/ExecuteTask.py --task Ukf --bids-data-dir $HOME/HCP/rawdata -c 1042 -s 1 \
--dwi-template sub-*/ses-*/dwi/*acq-PA*_dwi.nii.gz,sub-*/ses-*/dwi/*acq-AP*_dwi.nii.gz \
--num-workers 2 \
> $log/Ukf.txt 2>&1 &



### CTE ###

## structural pipeline ##
export LUIGI_CONFIG_PATH=`pwd`/test_params/struct_pipe_params.cfg

# test of StructMask
workflows/ExecuteTask.py --task StructMask --bids-data-dir $HOME/CTE/rawdata -c 1004 -s 01 \
--t2-template sub-*/ses-01/anat/*_T2w.nii.gz \
> $log/StructMask.txt 2>&1


# test of Freesurfer
workflows/ExecuteTask.py --task Freesurfer --bids-data-dir $HOME/CTE/rawdata -c 1004 -s 01 \
--t1-template sub-*/ses-01/anat/*_T1w.nii.gz --t2-template sub-*/ses-01/anat/*_T2w.nii.gz \
--num-workers 2 \
> $log/Freesurfer.txt 2>&1



## dwi pipeline ##
git checkout -- test_params/dwi_pipe_params.cfg
export LUIGI_CONFIG_PATH=`pwd`/test_params/dwi_pipe_params.cfg

# test of EddyEpi (FslEddy+PnlEpi)
workflows/ExecuteTask.py --task EddyEpi --bids-data-dir $HOME/CTE/rawdata -c 1004 -s 01 \
--dwi-template sub-*/ses-01/dwi/*_dwi.nii.gz --t2-template sub-*/ses-01/anat/*_AXT2.nii.gz \
> $log/EddyEpiUkf.txt 2>&1


# test of EddyEpi (PnlEddy+PnlEpi) and Ukf
# replace eddy_task in dwi_pipe_params
sed -i "s/eddy_task:\ FslEddy/eddy_task:\ PnlEddy/g" test_params/dwi_pipe_params.cfg
# delete *Ed_dwi.nii.gz, *EdEp_dwi.nii.gz, and *EdEp_bse.nii.gz
(( remove==1 )) && rm $HOME/CTE/derivatives/pnlpipe/sub-*/ses-*/dwi/*Ed*_dwi.nii.gz \
$HOME/CTE/derivatives/pnlpipe/sub-*/ses-*/dwi/*Ed*_bse.nii.gz

workflows/ExecuteTask.py --task Ukf --bids-data-dir $HOME/CTE/rawdata -c 1004 -s 01 \
--dwi-template sub-*/ses-01/dwi/*_dwi.nii.gz --t2-template sub-*/ses-01/anat/*_AXT2.nii.gz \
> $log/PnlEddy.txt 2>&1



## fs2dwi pipeline ##
export LUIGI_CONFIG_PATH=`pwd`/test_params/fs2dwi_pipe_params.cfg

# test of Wmql
# delete *Xc_T2w.nii.gz
(( remove==1 )) && rm $HOME/CTE/derivatives/pnlpipe/sub-*/ses-*/anat/*Xc_T2w.nii.gz
workflows/ExecuteTask.py --task Wmql --bids-data-dir $HOME/CTE/rawdata -c 1004 -s 01 \
--dwi-template sub-*/ses-*/dwi/*EdEp_dwi.nii.gz --t2-template sub-*/ses-*/anat/*_T2w.nii.gz \
> $log/Wmql.txt 2>&1

# test of TractMeasures
workflows/ExecuteTask.py --task TractMeasures --bids-data-dir $HOME/CTE/rawdata -c 1004 -s 01 \
--dwi-template sub-*/ses-*/dwi/*EdEp_dwi.nii.gz --t2-template sub-*/ses-*/anat/*_T2w.nii.gz \
> $log/TractMeasures.txt 2>&1

fi


### equivalence tests ###

function equality_tests() {

# nifti
for i in `find . -name fs2dwi -prune -false -o -name *.nii.gz`
do
    pytest -v -s test_luigi.py -k "test_header or test_data" --filename $i --outroot ~
done

# wmparc
for i in `find . -name wmparc*`; do pytest -v -s test_luigi.py -k test_wmparc --filename $i --outroot ~; done

# bvals and bvecs
for i in `find . -name *.bval`; do pytest -v -s test_luigi.py -k test_bvals --filename $i --outroot ~; done

for i in `find . -name *.bvec`; do pytest -v -s test_luigi.py -k test_bvecs --filename $i --outroot ~; done

# tracts
for i in `find . -name sub-1042*EdEp_bse.nii.gz`,`find . -name sub-1042*EdEp.vtk`
do
    pytest -v -s test_luigi.py -k test_tracts --filename $i --outroot ~
done

# wmql tract measures
for i in `find . -name *.csv`; do pytest -v -s test_luigi.py -k test_wmql --filename $i --outroot ~; done

# json
for i in `find . -name *.json`; do pytest -v -s test_luigi.py -k test_json --filename $i --outroot ~; done

# html
for i in `find . -name *.html`; do pytest -v -s test_luigi.py -k test_html --filename $i --outroot ~; done

}


cd tests
if [[ ! -z $console_print ]]
then
    equality_tests
else
    pytest_log=../$log/pytest-${datestamp}.txt
    
    {
    equality_tests
    } > $pytest_log 2>&1
    
    # email only pytest log
    for u in $to
    do
        cat $pytest_log | mailx -s "luigi-pnlpipe test results" \
        -a $pytest_log -- $u@bwh.harvard.edu
    done
    
fi


