#!/bin/bash

#DSET="GSWP3 PGFv2 WATCH WATCH+WFDEI"
DSET="WATCH"

# Path of 30 year detrended time series
DTR_PATH=/home/buechner/isimip_iplex/inputdata_ISI-MIP2/$DSET/detrended
# Target path
TGT_PATH=/home/buechner/isimip_iplex/inputdata_ISI-MIP2/$DSET/random

mkdir -p $TGT_PATH/tmp
CDO="cdo -s -z zip"
DSET_LC=$(echo $DSET | tr '[:upper:]' '[:lower:]')
. ./years_static.txt

for VAR in $(ls $DTR_PATH |cut -d"_" -f1|uniq);do
    case $VAR in
        pr|prsn)
            VAR=${VAR}_gpcc;;
    esac
    VARLIST="$VARLIST $VAR"
done

DEFAULT_VAR="1"
VAR_ARRAY=( $VARLIST )
echo;echo "Select variable to process:"
#echo "0) ALL"
VAR_LEN=$((${#VAR_ARRAY[@]} - 1))
for VAR_ID in $(seq 0 $VAR_LEN);do
    echo $(($VAR_ID + 1))")" ${VAR_ARRAY[$VAR_ID]}
done
VAR_ID="-1"
while [ $VAR_ID -lt 0 -o $VAR_ID -gt $(($VAR_LEN + 1)) ];do
    read -e -p "option : " VAR_ID
done
VAR=${VAR_ARRAY[$(($VAR_ID - 1))]}
echo

read -e -p "Number of years: " NUM_YEARS;echo
TYPE_YEARS=S
echo -n "Use static or random set of years [S/r] : "
read INPUT
[ -n "$INPUT" ] && TYPE_YEARS=$INPUT

NCDF_STARTYEAR=$((1901 - $NUM_YEARS))
if [[ $TYPE_YEARS == "S" ]];then
    NUMBERS=$(echo $YEARS_STATIC|cut -d " " -f1-$((NUM_YEARS + 1))|tac -s " ")
else
    RANGE=29;YEAR=0
    while [[ $YEAR -le $NUM_YEARS ]];do
        NUMBER=$RANDOM;let "NUMBER %= $RANGE + 1"
        [[ $NUMBER -gt 8 ]] && NUMBERS="$NUMBERS 19$((NUMBER + 1))" || NUMBERS="$NUMBERS 190$((NUMBER + 1))"
        YEAR=$(($YEAR + 1))
    done
fi

for FILE in $DTR_PATH/${VAR}_${DSET_LC}_*_detrended.nc4;do
    echo " spliting $FILE ..."
    $CDO -splityear \
        $FILE \
        $TGT_PATH/tmp/$(basename $FILE .nc4).
done

rm -rf $TGT_PATH/$NUM_YEARS.random.nc4
echo;echo "concatenating random years..."
$CDO -cat \
    $(for YEAR in $NUMBERS;do ls $TGT_PATH/tmp/${VAR}_*_detrended.$YEAR.nc4;done) \
    $TGT_PATH/${VAR}_${NUM_YEARS}years.random.nc4
TMPFILE=$TGT_PATH/${VAR}_${NUM_YEARS}years.random.settaxis.nc4
rm -f $TMPFILE
while [ ! -e $TMPFILE ];do
    echo "setting time axis..."
    $CDO -selyear,$NCDF_STARTYEAR/1900 -settaxis,$NCDF_STARTYEAR-01-01,00:00:00,1days \
        $TGT_PATH/${VAR}_${NUM_YEARS}years.random.nc4 \
        $TMPFILE
    [[ $? != 0 ]] && rm -f $TMPFILE && echo "!error, try again..."
done && rm -f $TGT_PATH/${VAR}_${NUM_YEARS}years.random.nc4

echo "split to decadal time slices"
FIRST=$NCDF_STARTYEAR
DIFF_YEARS=$((1900 - $NCDF_STARTYEAR))
DIFF_YEARS=$(echo $DIFF_YEARS |rev |cut -c 1)
while [[ $FIRST -lt 1900 ]];do
    if [[ $DIFF_YEARS -ne "9" ]];then
        LAST=$(($NCDF_STARTYEAR + $DIFF_YEARS))
        DIFF_YEARS=9
    else
        LAST=$(($FIRST + 9))
    fi

    echo "split years $FIRST to $LAST"
    $CDO -selyear,$FIRST/$LAST \
        $TMPFILE \
        $TGT_PATH/${VAR}_${DSET_LC}_${FIRST}_${LAST}_detrended.random.nc4

    echo " fix attributes..."
    ncatted -O -h \
        -a history,global,d,, \
        $TGT_PATH/${VAR}_${DSET_LC}_${FIRST}_${LAST}_detrended.random.nc4

    FIRST=$(($LAST + 1))
done && rm -rf $TGT_PATH/${VAR}_${NUM_YEARS}years.random.* $TGT_PATH/tmp
echo "...done"
