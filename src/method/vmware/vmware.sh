#!/bin/sh
#
#   vmware.sh - vmware esx/esxi backup method handler
#
#   Copyright (C) 2003-2008 InitZero S.r.l.
#   Written by: Ugo Viti <ugo.viti@initzero.it>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


# import config fields
config_field_import backup_source_uri uri  notnull	"${usr_file_conf}" keep

# trim out invalid or dangerous characters from backup_source variable
[ "${backup_source}" != "*" ] && backup_source=$(echo ${backup_source} | tr -d ["/"])

# mandatory commands
backup_method_cmds="ssh"
backup_method_opts_ssh="-o BatchMode=yes -o StrictHostKeyChecking=no -o ForwardX11=no"


# variables useful to this method
backup_method_cmd="vim-cmd"
backup_method_opts=""

backup_name_prefix="backup"
backup_name_suffix="$(show_time_human ${time_begin} backup)"
backup_name="${backup_name_prefix}-${system}"
backup_destination_latest="${backup_destination}/${backup_name}"
backup_destination_step="${backup_destination_latest}-${backup_name_suffix}"
backup_name_extension=""

method_init(){
    # verify if all commands are installed in the system paths
    for cmd in $backup_method_cmds 
      do
        which $cmd >/dev/null 2>&1
        [ $? -ne 0 ] && echo "the command '$cmd' doesn't exist in any path, please install it and retry" && exit 1
    done

    #local extra_option_right="split, all"
    current_option="${method_option}"
    # if the -M switch is not used, then assume current_option=all
    #[ -z "${current_option}" ] && current_option="all" && method_option="all"
    #[[ "${current_option}" != "split" && "${current_option}" != "all" ]] && report_text extra_option_required && exit 1

    #case $current_option in
    #    split)     backup_method_opts_extra="$backup_method_opts_extra";;
    #    all)       backup_method_opts_extra="$backup_method_opts_extra";;
    #    *)         report_text extra_option_wrong && exit 1 ;;
    #esac

    # the mysql backup method is always 'remote'
    import_backup_source_uri_variables "${backup_source_uri}"

    # adapt the backup method to protocol used
    if   [ "${backup_source_uri_protocol}" = "vmware" ]
     then
       #[ -n "${backup_source_uri_host}" ]		&& backup_method_opts_extra="${backup_method_opts_extra} -h ${backup_source_uri_host}"
       #[ -n "${backup_source_uri_username}" ]	&& backup_method_opts_extra="${backup_method_opts_extra} -u ${backup_source_uri_username}"
       #[ -n "${backup_source_uri_password}" ]	&& backup_method_opts_extra="${backup_method_opts_extra} --password=${backup_source_uri_password}"
       #[ -n "${backup_source_uri_port}" ]		&& backup_method_opts_extra="${backup_method_opts_extra} -P ${backup_source_uri_port}"
       backup_method_opts_extra="${backup_method_opts_extra}"
     else
      report_text uri_unsupported
      report_text protocol_unsupported
      return 1;
    fi

    # If is given a URI then check first if the remote host is reachable
    check_status_host "${backup_source_uri}"
    save_status_host
 save_method_info
}
method_init ; [ $? -eq 1 ] && exit 1; # exit if an error occour on method_init function

# the real backup method comand to run
method_backup() {
 make_backup_step(){
   # if not exist backup_destination_step, make it
   [ ! -e "${backup_destination_step}" ] && mkdir -p "${backup_destination_step}"

   # empty the 'backup_source_step' variable if this is a --all-databases dump
   backup_source_step_orig=${backup_source_step}
   #[ "${backup_source_step}" = "all-databases" ] && backup_source_step=""

   eval ${backup_method_cmd} ${backup_method_opts_default} ${backup_method_opts} ${backup_method_opts_extra} ${backup_source_step}

   # restore the right backup_source_step variable
   backup_source_step=${backup_source_step_orig}

   save_size_destination "${backup_destination_step}"
   save_size_backup "${size_destination}" varreplace
 }

 # connect to the mysql server and generate a list of all databases and parse out the excluded databases
 generate_vm_list(){
   generate_vm_list_step() {
     backup_source=$(mysql ${backup_method_opts_extra} --batch --execute="show databases;" | grep -v ^"Database"$ | grep -v ^"information_schema"$ | grep -wvf ${file_list_exclude} | tr -s "\n" " " | sed 's/^ *//g' | sed 's/ *$//g')
   }
   save_time_begin_step
   generate_vm_list_step 1>/dev/null 2>"${file_log_errors_step}"
   report_text generate_vm_list
   save_time_end_step
   check_status_step
   report_text separator_info3
 }

 make_backup_step_init() {
   # right now not needed
   #[ $(check_status_step >/dev/null 2>&1 ; echo $?) -gt 0 ] && return 1;

   #echo backup_exclude=$backup_exclude
   #echo backup_source_step=$backup_source_step
   backup_destination_step="${backup_destination}"/"${backup_name_prefix}-${system}-${backup_source_step}-${backup_name_suffix}.${backup_name_extension}.bz2"
   save_time_begin_step
   report_text backup_step
   make_backup_step > ${file_log_errors_step} 2>&1
   save_time_end_step
   check_status_backup_step
   report_text separator_info3
 }

 method_erase() {
   # auto erasing old backups
   save_time_begin_step
   backup_erase_init "${backup_name_prefix}-${system}-${backup_source_step}-"
   report_text backup_erase
   backup_erase > ${file_log_errors_step} 2>&1
   save_time_end_step
   check_status_step
   report_text separator_info3
 }


if [ ${status_host} = 0 ]
  then
    #echo "current_option: $current_option"
    case $current_option in
  esx|esxi)
    [ "${backup_source}" = "*" ] && backup_source=""
    [ -z "${backup_source}" ] && generate_vm_list
    #echo "to backup: \"${backup_source}\""
    for backup_source_step in ${backup_source} ; do make_backup_step_init ; method_erase ; done
    unset backup_source_step
    ;;
    esac
  else
    report_text separator_info4
    report_text status_host_down
    save_status_backup_error
    report_text separator_info4
fi
}


## Backup and Text Reporting Procedure

save_time_begin		# save the begin time

report_text separator_info1
report_text system
report_text method
report_text method_option
report_text method_type
[ -n "${backup_source_uri}" ] && report_text backup_source_uri
report_text backup_source
report_text backup_destination
report_text backup_exclude
report_text backup_method_opts
report_text backup_keep
report_text synbak_server
report_text synbak_server_kernel
report_text synbak_version
report_text technical_support
report_text time_start
report_text separator_info2

if ! check_writable "${backup_destination}" 2>/dev/null
  then
    report_text separator_error
    check_writable "${backup_destination}"
    save_status_backup_error
    report_text separator_error
    report_text separator_info2
    save_time_end       # save the end time
    report_text time_end
    report_text status_backup
    report_text separator_info1
    return 1
elif ! check_cuncurrent_limit >/dev/null 2>&1
  then
    report_text separator_error
    check_cuncurrent_limit
    save_status_backup_error
    report_text separator_error
    report_text separator_info2
    save_time_end
    report_text time_end
    report_text status_backup
    report_text separator_info1
    return 1
  else
    ## begin backup
    method_backup
    sleep 1
    save_size_destination "${backup_destination}/*${backup_name_suffix}*"
    set_stats_backup
    ## end backup
fi


report_text system_info

save_time_end		# save the end time
save_time_duration	# save the duration time

report_text separator_info2
report_text time_end
report_text size_backup
report_text speed_backup
report_text size_destination
report_text time_duration
report_text status_backup

report_text separator_info1

