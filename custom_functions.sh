#!/bin/bash

function screen_shot() {
  mkdir -p ~/.screenshot
  FILE_NAME="~/.screenshot/"$(date "+%Y%m%d%H%M%S-%N")".png"
  import $FILE_NAME && xclip -selection clipboard -target image/png $FILE_NAME
}

function aws_enc() {
  aws kms encrypt --key-id alias/general-secret-passing --plaintext "$1" --output text --query CiphertextBlob
}

function aws_dec() {
  TEMP_BINARY_FILE=$(uuidgen)
  echo $1 | base64 --decode > $TEMP_BINARY_FILE
  aws kms decrypt --ciphertext-blob fileb://$TEMP_BINARY_FILE --output text --query Plaintext --region ap-southeast-2 | base64 --decode
  echo
  rm $TEMP_BINARY_FILE
}

function dec_api_key() {
  TMP_BIN_FILE=".tmp.kms.encrypted.bin.$RANDOM"
  echo $1 | xxd -r -p - $TMP_BIN_FILE
  aws kms decrypt --ciphertext-blob fileb://$TMP_BIN_FILE --output text --query Plaintext --region ap-southeast-2 | base64 --decode
  rm -f $TMP_BIN_FILE
}

function jqf() {
   echo $1 | jq .
}

function list_ecr_images() {
  if [ -z $1 ]; then
    echo "usage: list_ecr_images <repo>"
    return 1
  fi
  aws ecr describe-images --query 'sort_by(imageDetails,& imagePushedAt)[*]' --repository-name $1-service
}

#source ~/dev/tool/aws-cli-mfa/clearaws
#source ~/dev/tool/aws-cli-mfa/getaws
#alias awstoken="getaws default"
awstoken() {
  identity=$(aws sts get-caller-identity --profile original)
  username=$(echo -- "$identity" | sed -n 's!.*"arn:aws:iam::.*:user/\(.*\)".*!\1!p')
  echo You are: $username >&2

  mfa=$(aws iam list-mfa-devices --user-name "$username" --profile original)
  device=$(echo -- "$mfa" | sed -n 's!.*"SerialNumber": "\(.*\)".*!\1!p')
  echo Your MFA device is: $device >&2
  echo -n "Enter your MFA code now: " >&2
  read code
  tokens=$(aws sts get-session-token --serial-number "$device" --token-code $code --profile original)
  secret=$(echo -- "$tokens" | sed -n 's!.*"SecretAccessKey": "\(.*\)".*!\1!p')
  session=$(echo -- "$tokens" | sed -n 's!.*"SessionToken": "\(.*\)".*!\1!p')
  access=$(echo -- "$tokens" | sed -n 's!.*"AccessKeyId": "\(.*\)".*!\1!p')
  expire=$(echo -- "$tokens" | sed -n 's!.*"Expiration": "\(.*\)".*!\1!p')
  TEMP=$(uuidgen)
  sed -n 1,3p ~/.aws/credentials >~/.$TEMP
  echo "[default]" >>~/.$TEMP
  echo "aws_access_key_id=$access" >>~/.$TEMP
  echo "aws_secret_access_key=$secret" >>~/.$TEMP
  echo "aws_session_token=$session" >>~/.$TEMP

  mv ~/.$TEMP ~/.aws/credentials

  echo Keys valid until $expire >&2

  # login ecr
  $(echo $(aws ecr get-login --region ap-southeast-2) | sed -e 's/-e none //g')
}

alias gcmsg 2>/dev/null >/dev/null && unalias gcmsg
gcmsg() {
  repo_name=$(basename $(git rev-parse --show-toplevel))
  if [[ "$?" != "0" ]]; then
    return $?
  fi
  # prepend sub-project name to the git commit message only if we are in sub-prodjct in mono repo
  prefix_msg=""
  if [[ ! -d $PWD/.git && ( "$repo_name" == "commons" || "$repo_name" == "mono-project" ) ]]; then
    last_dir=$PWD
    dir=$PWD/..
    while [[ ! -d $dir/.git ]]; do
      if [[ "$(readlink -f $dir)" == "/" ]]; then
        break
      fi
      last_dir=$dir
      dir=$dir/..
    done

    sub_project_name=$(basename $(readlink -f $last_dir))
    if [[ -n $sub_project_name && "$sub_project_name" != "/" ]]; then
      prefix_msg="["$(echo $sub_project_name | tr a-z A-Z)"] "
    fi
  fi
  git commit -m $prefix_msg$1
}

gdl() {
	if [[ "$#" -eq 1 || "$#" -eq 2 ]]; then
		GDL_CMD="./gradlew"
		GDL_OPTS="--no-daemon --no-build-cache"
	  SUB_PROJ_PREFIX=""
	  if [[ "$#" -eq 2 ]]; then
	    SUB_PROJ_PREFIX=":"$2":"
	  fi
    case $1 in
	    c)
        bash -c "$GDL_CMD $GDL_OPTS ${SUB_PROJ_PREFIX}clean"
	      ;;
	    cc)
        bash -c "$GDL_CMD $GDL_OPTS ${SUB_PROJ_PREFIX}clean ${SUB_PROJ_PREFIX}compileJava"
	      ;;
	    ct)
        bash -c "$GDL_CMD $GDL_OPTS ${SUB_PROJ_PREFIX}clean ${SUB_PROJ_PREFIX}test"
	      ;;
	    cb)
        bash -c "$GDL_CMD $GDL_OPTS ${SUB_PROJ_PREFIX}clean ${SUB_PROJ_PREFIX}build"
	      ;;
	    cj)
        bash -c "$GDL_CMD $GDL_OPTS ${SUB_PROJ_PREFIX}clean ${SUB_PROJ_PREFIX}jib"
	      ;;
	    lq)
        bash -c "$GDL_CMD $GDL_OPTS ${SUB_PROJ_PREFIX}clean ${SUB_PROJ_PREFIX}diffChangeLog"
	      ;;
	    *)
	      echo "Usage: gdl <c|cc|ct|cb|cj> [sub_project_name]"
    esac
  else
	  echo "Usage: gdl <c|cc|ct|cb|cj> [sub_project_name]"
  fi
}
