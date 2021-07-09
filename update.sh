#!/bin/bash

last_missing=""

function get_pdf()
{
	local localfile="$1".pdf
	if [[ -e ${localfile} ]]; then
		if [[ ! -s ${localfile} ]]; then
			echo "removing empty file ${localfile}"
			rm "${localfile}"
		else
			return 0
		fi
	fi

	if [[ $1 == $last_missing ]]; then
		# skip known missing files
		return 1
	fi
	
	local notify=0
	local url="https://www.health.pa.gov/topics/Documents/Diseases%20and%20Conditions/COVID-19%20County%20Data"
	local flags="-O ${localfile}"
	local fileroot=(
		"County%20Case%20Counts_"
		"County%20Case%20Counts%20"
		"County%20Counts_"
		"County%20Counts%20"
	)

	if [[ ${VERBOSE} -eq 0 ]]; then
		flags="-q ${flags}"
	fi
	
	#
	# PA DoH is bad at data consistency. The filenames may or may not have
	# leading 0s for month and day. Sometimes they use underscores,
	# sometimes hyphens. Test all possibilities.
	#

	local dates=(
		"${1}"						# date mm-dd-yyyy
		"${1##0}"					# no leading 0 in month
		"${1/-0/-}"					# no leading 0 in day
	)

	dates+=(
		"${dates[1]/-0/-}"			# no leading 0 in month or day
	)

	dates+=(
		"${dates[0]/%2021/21}"		# 2 digit year
		"${dates[1]/%2021/21}"
		"${dates[2]/%2021/21}"
		"${dates[3]/%2021/21}"
	)

	seperators=('_' ' ' '.')
	for s in "${seperators[@]}"; do
		dates+=(
			"${dates[0]//-/$s}"		# date mm<$s>dd<$s>yyyy
			"${dates[1]//-/$s}"		# no leading 0 in month w/ seperator
			"${dates[2]//-/$s}"		# no leading 0 in day w/ seperator
			"${dates[3]//-/$s}"		# no leading 0s w/ seperator
			"${dates[4]//-/$s}"		# date mm<$s>dd<$s>yy
			"${dates[5]//-/$s}"		# no leading 0 in month w/ seperator, 2 digit year
			"${dates[6]//-/$s}"		# no leading 0 in day w/ seperator, 2 digit year
			"${dates[7]//-/$s}"		# no leading 0s w/ seperator, 2 digit year
		)
	done

	local filename=""

	while true; do
		for base in "${fileroot[@]}"; do
			for date in "${dates[@]}"; do
				filename="${base}${date}.pdf"
				if ! wget ${flags} "${url}/${filename}"; then
					rm "$localfile"
				else
					if [[ $VERBOSE -eq 1 ]]; then
						echo "${url}/${filename}"
					fi
					# found it! break all the way out of the while
					break 3
				fi
			done
		done

		if [[ $notify -eq 0 ]]; then
			if [[ $(date +"%m-%d-%Y") == "$1" ]]; then
				echo "waiting on $1..."
				notify=1
			elif [[ $(date -d"yesterday" +"%m-%d-%y") == "$1" ]] && [[ $WAIT -eq 1 ]]; then
				echo "waiting for yesterday's results ($1)..."
				notify=1
			else
				echo "couldn't find $1"
				last_missing=$1
				return 1
			fi
		fi

		sleep 60
	done

	if [[ $notify -eq 1 ]]; then
		echo "${filename}"
		date
		(aplay -q NOTIFY.WAV &)
	fi
}

function split_line()
{
	local -n cases=$2
	local -n confirmed=$3
	local -n probable=$4
	local -n negative=$5

	cases=$(echo "$1" | awk '{print $3}')
	confirmed=$(echo "$1" | awk '{print $4}')
	probable=$(echo "$1" | awk '{print $5}')
	negative=$(echo "$1" | awk '{print $6}')

	#
	# strip any commas from the numbers
	#
	cases=${cases//,/}
	confirmed=${confirmed//,/}
	probable=${probable//,/}
	negative=${negative//,/}
}

function update_covid19()
{
	d=$(date --date "$1" "+%m-%d-%Y")
	d0=$(date --date="${d//-/\/} - 1 day" "+%m-%d-%Y")

	declare today_cases
	declare today_confirmed
	declare today_probable
	declare today_negative

	declare yesterday_cases
	declare yesterday_confirmed
	declare yesterday_probable
	declare yesterday_negative

	local new_case_count=""
	
	if get_pdf "${d0}"; then
		local yesterday_centre
		yesterday_centre=$(pdfgrep -i "centre" "${d0}".pdf)
		split_line "$yesterday_centre" yesterday_cases yesterday_confirmed yesterday_probable yesterday_negative
	fi

	if get_pdf "$d"; then
		local today_centre
		today_centre=$(pdfgrep -i "centre" "$d".pdf)
		split_line "$today_centre" today_cases today_confirmed today_probable today_negative
	fi

	if [[ ! -e $d.pdf ]]; then
		return 1
	fi

	if [[ -e $d0.pdf ]]; then
		new_case_count="($((today_cases - yesterday_cases)))"
	fi

	if [[ ${HEADER} -eq 1 ]]; then
		printf "date\t\ttotal cases\tconfirmed\tprobable\tnegative\tchange since yesterday\n"
		printf "==========\t===========\t=========\t========\t========\t======================\n"
		HEADER=0
	fi

	printf "%s\t%i\t\t%i\t\t%i\t\t%i\t\t%s\n" "$d" "$today_cases" "$today_confirmed" "$today_probable" "$today_negative" "$new_case_count"
}

VERBOSE=0
RECURSIVE=0
HEADER=0
WAIT=0

function usage()
{
	echo "update.sh [-r] [-v] [-h] [date]"
	echo "	-r		fetch data recursively from the given date until today"
	echo "	-v		verbose logging"
	echo "	-h		print column headers"
	echo "  -w		wait for yesterday's results"
}

opts='rvh'
while getopts $opts op
do
	case $op in
		r) RECURSIVE=1;;
		v) VERBOSE=1;;
		h) HEADER=1;;
		w) WAIT=1;;
		?) usage; exit;;
		:) echo "Unknown option: -$OPTARG" >&2; exit 1;;
	esac
done

shift $((OPTIND - 1))

update_covid19 "$1";

if [[ $RECURSIVE == 1 ]]; then
	dt=$1
	today=$(date +%s)
	while true; do
		dt=$(date --date "$dt + 1 day" "+%m/%d/%Y")
		if [[ $(date -d "$dt" +%s) -gt $today ]]; then
			break
		fi
		update_covid19 "$dt"
	done
fi
