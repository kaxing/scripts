#/usr/bin/env bash

# lh-uninstall-helper.sh: an uninstall helper for longhorn deploy via kubectl

# Set default values
NAMESPACE="longhorn-system"

# Check required cli tools
missing_command=0; for command in grep sed kubectl jq curl; do
	command -v $command 2&>1 >/dev/null || ( ((missing_command+=1)) && echo "Command: $command is missing." )
done; [ $missing_command -gt 0 ] && echo "Please install missing command(s)." && exit 1


help() {
	echo "Usage: lh-uninstall-helper.sh function-name"
	declare -F|cut -d' ' -f3|grep -Ev "help|\-h|\-\-"| sed 's/^/\t/'
}; --help() { help; }; -h() ( --help;)

get-installed-version() {
	local version
	version="$(kubectl get settings.longhorn.io/current-longhorn-version -n $NAMESPACE --no-headers -o custom-columns=":.value" )"
	
	local counter=0
	while [[ -z $version ]]; do
		>&2 echo "Trying to use default-engine-image as the installed version might be older than v1.2.3"
		# Note: for v1.1.3 and older there is no current-longhorn-version so try to use the default-engine-image instead
		version="$(kubectl get settings.longhorn.io/default-engine-image -n $NAMESPACE  --no-headers -o custom-columns=":.value"|cut -d':' -f2)"
		((counter++)) && [ $counter -eq 3 ] && >&2 echo "Retry $counter Failed to get the installed version" && exit 1
	done 

	echo "$version" 
}


deploy-uninstall-job-by-version() {
	local branch="$@"
	[ -z "$branch" ] && >&2 echo "No version specified for uninstaller" && exit 1
	
	echo "Fetching and creating longhorn-uninstall job.."
	kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn-manager/$branch/deploy/uninstall/uninstall.yaml
	kubectl get jobs -n default
}


check-if-any-volumes-exist() {
	
	local exist=$(kubectl get volumes -n $NAMESPACE --no-headers -o custom-columns=":.metadata.name"|wc -l|tr -d " ")
	
	if [ $exist -gt 0 ]; then
		echo "There are $exist volumes in namespace $NAMESPACE"
		echo "It is recommended to delete all the volumes and related workload before uninstallation."
		exit 1
	else
		echo "There are no Longhorn Volume in namespace $NAMESPACE"
	fi

}


wait-for-uninstaller-job-complete-then-cleanup() {
	local timeout="$@"
	echo "Waiting for uninstaller job to complete.."
	kubectl wait --for=condition=complete --timeout=$timeout -n default job/longhorn-uninstall
	kubectl delete job/longhorn-uninstall -n default
}


remove-the-rest-of-components() {
	local branch="$@"
	echo "Deleteing the rest of the components with the installation manifest with version: $branch"
	kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn-manager/$branch/deploy/uninstall/uninstall.yaml
	kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/$branch/deploy/longhorn.yaml
}


uninstall-as-suggested(){

	check-if-any-volumes-exist

	target_version=$(get-installed-version)
	echo "Uninstalling Longhorn $target_version ..."

	if [[ "$target_version" == *"-dev" ]]; then
  		echo "This is a dev version: $target_version, will use master image instead.."
		target_version="master"
	fi

	echo "Longhorn $target_version will be removed from $(kubectl config current-context) cluster"
	read -p "Press enter to continue.."

	deploy-uninstall-job-by-version $target_version
	wait-for-uninstaller-job-complete-then-cleanup 15m

	remove-the-rest-of-components $target_version

	# wait-for-unistall-job-complete

	# delete-manifest-by-version $target_version

	# force-cleanup-crds 

	echo "Please wait for namespace: $NAMESPACE to be deleted"
	kubectl delete namespace/$NAMESPACE --wait=true

}



# Run standard uninstall workflow when there is no specific function assigned

[ -z "$1" ] && { echo "No arguments provided, proceeding with suggested uninstall steps" && uninstall-as-suggested; } || $@
