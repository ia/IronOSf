#!/usr/bin/env bash

# little helper for docker deployment to:
# - start development environment for IronOS ("shell" sub-command)
# - generate full set of builds ("build" sub-command)
# - probably doing some other routines (check source briefly before running undocumented commands!)

#set -x
#set -e

### helper functions

# brief help (some supported commands may be missing!)
usage()
{
	echo -e "\nUsage: ${0} [CMD]\n"
	echo "CMD (docker related):"
	echo -e "\tshell - start docker container with shell inside to work on IronOS with all tools needed"
	echo -e "\tbuild - compile builds of IronOS inside docker container for supported hardware"
	echo -e "\tclean - delete created docker image for IronOS & its build cache objects\n"
	echo "CMD (helper routines):"
	echo -e "\tdocs - high level target to run docs_readme and docs_history (see below)\n"
	echo -e "\tdocs_readme - generate & OVERWRITE(!) README.md inside Documentation/ based on nav section from mkdocs.yml if it changed\n"
	echo -e "\tdocs_history - check if History.md has the changelog for the latest stable release\n"
	echo -e "\tcheck_style_file SRC - run code style checks based on clang-format & custom parsers for source code file SRC\n"
	echo -e "\tcheck_style_log - run clang-format using source/Makefile and generate gcc-compatible error log in source/check-style.log\n"
	echo -e "STORAGE NOTICE: for \"shell\" and \"build\" commands extra files will be downloaded so make sure that you have ~5GB of free space.\n"
}

# Documentation/README.md automagical generation routine
docs_readme()
{
	# WARNING: ON RUN Documentaion/README.md MAY BE OVERWRITTEN WITHOUT ANY WARNINGS / CONFIRMATIONS !!!
	# Returns:
	## 0 to the environment & silence - if there are no any changes in README.md nor updates in mkdocs.yml
	## 1 to the environment (as error) & note message - if the update of README.md in repo is required
	yml="scripts/IronOS-mkdocs.yml"
	md_old="Documentation/README.md"
	md_new="Documentation/README"
	# ^^^^ hardcoded paths relative to IronOS/ to make this func very trivial
# file overwritten section looks out of style but hoping to make shellcheck happy
cat << EOF > "${md_new}"

<!-- THIS FILE IS AUTOGENERATED by "scripts/deploy.sh docs_readme" based on nav section in ${yml} config -->
<!-- THIS FILE IS NOT SUPPOSED TO BE EDITED MANUALLY -->

#### This is autogenerated README for brief navigation through github over official documentation for IronOS project
#### This documentation is also available [here online](https://ralim.github.io/IronOS)

EOF
	# it probably will become unexplainable in a few months but so far it works:
	sed '1,/^nav/d; /^ *$/,$d; s,- ,- [,; s,: ,](../Documentation/,; s,.md,.md),; s,:$,],; s,/Pinecil ,/Pinecil%20,; /^  - \[.*\]$/ s,\[,,; s,]$,,' "${yml}" >> "${md_new}"
	ret=0
	if [ -z "$(diff -q "${md_old}" "${md_new}")" ]; then
		rm "${md_new}"
		ret=0
	else
		mv "${md_new}" "${md_old}"
		echo ""
		echo "${yml} seems to be updated..."
		echo "... while ${md_old} is out-of-date!"
		echo ""
		echo "Please, update ${md_old} in your local working copy by command:"
		echo ""
		echo " $ ./scripts/deploy.sh docs_readme"
		echo ""
		echo "And then commit & push changes to update ${md_old} in the repo:"
		echo ""
		echo " $ git commit ${md_old} -m \"${md_old}: update autogenerated file\" && git push"
		echo ""
		ret=1
	fi;
	return "${ret}"
}

# Documentation/History.md automagical changelog routine
docs_history()
{
	md="Documentation/History.md"
	ver_md="$(sed -ne 's/^## //1p' "${md}" | head -1)"
	echo "Latest changelog: ${ver_md}"
	ver_git="$(git tag -l | sort | grep -e "^v" | grep -v "rc" | tail -1)"
	git tag -l
	echo "Latest release tag: ${ver_git}"
	ret=0
	if [ "${ver_md}" != "${ver_git}" ]; then
		ret=1
		echo "It seems there is no changelog information for ${ver_git} in ${md} yet."
		echo "Please, update changelog information in ${md}."
	fi;
	return "${ret}"
}

# Helper function to check code style using clang-format & grep/sed custom parsers:
# - basic logic moved from source/Makefile : `check-style` target for better maintainance since a lot of sh script involved;
# - output goes in gcc-like error compatible format for IDEs/editors.
check_style_file()
{
	ret=0
	src="${1}"
	test ! -f "${src}" && echo "ERROR!!! Provided file ${src} is not available to check/read!!!" && exit 1
	# count lines using diff between beauty-fied file & original file to detect format issue
	var="$(clang-format "$src" | diff "$src" - | wc -l)"
	if [ "${var}" -ne 0 ]; then
		# show full log error or, if LIST=anything provided, then show only filename of interest (implemented for debug purposes mainly)
		if [ -z "${LIST}" ]; then
			# sed is here only for pretty logging
			clang-format "${src}" | diff "${src}" - | sed 's/^---/-------------------------------------------------------------------------------/; s/^< /--- /; s/^> /+++ /; /^[0-9].*/ s/[acd,].*$/ERROR1/; /^[0-9].*/ s,^,\n\n\n\n'"${src}"':,; /ERROR1$/ s,ERROR1$,:1: error: clang-format code style mismatch:,; '
		else
			echo "${src}"
		fi;
		ret=1
	fi;
	return "${ret}"
}

# check_style routine for those who too lazy to do it everytime manually
check_style_log()
{
	log="source/check-style.log"
	make  -C source  check-style  2>&1  |  tee  "${log}"
	chmod  0666  "${log}"
	sed -i -e 's,\r,,g' "${log}"
	return 0
}

### main

docker_conf="Env.yml"

# get absolute location of project root dir to make docker happy with config(s)
# (successfully tested on relatively POSIX-compliant Dash shell)

# this script
script_file="/deploy.sh"
# IronOS/scripts/deploy.sh
script_path="${PWD}"/"${0}"
# IronOS/scripts/
script_dir=${script_path%"${script_file}"}
# IronOS/
root_dir="${script_dir}/.."
# IronOS/Env.yml
docker_file="-f ${root_dir}/${docker_conf}"

# allow providing custom path to docker tool using DOCKER_BIN external env. var.
# (compose sub-command must be included, i.e. DOCKER_BIN="/usr/local/bin/docker compose" ./deploy.sh)

if [ -z "${DOCKER_BIN}" ]; then
	docker_app=""
else
	docker_app="${DOCKER_BIN}"
fi;

# detect availability of docker

docker_compose="$(command -v docker-compose)"
if [ -n "${docker_compose}" ] && [ -z "${docker_app}" ]; then
	docker_app="${docker_compose}"
fi;

docker_tool="$(command -v docker)"
if [ -n "${docker_tool}" ] && [ -z "${docker_app}" ]; then
	docker_app="${docker_tool}  compose"
fi;

# give function argument a name

cmd="${1}"

# meta target to verify markdown documents

if [ "docs" = "${cmd}" ]; then
	docs_readme
	readme="${?}"
	docs_history
	hist="${?}"
	if [ "${readme}" -eq 0 ] && [ "${hist}" -eq 0 ]; then
		ret=0
	else
		ret=1
	fi;
	exit ${ret}
fi;

# if only README.md for Documentation update is required then run it & exit

if [ "docs_readme" = "${cmd}" ]; then
	docs_readme
	exit "${?}"
fi;

# if only History.md for Documentation update is required then run it & exit

if [ "docs_history" = "${cmd}" ]; then
	docs_history
	exit "${?}"
fi;

if [ "check_style_file" = "${cmd}" ]; then
	check_style_file "${2}"
	exit "${?}"
fi;

if [ "check_style_log" = "${cmd}" ]; then
	check_style_log
	exit "${?}"
fi;

# if docker is not presented in any way show warning & exit

if [ -z "${docker_app}" ]; then
	echo "ERROR: Can't find docker-compose nor docker tool. Please, install docker and try again."
	exit 1
fi;

# construct command to run

if [ -z "${cmd}" ] || [ "${cmd}" = "shell" ]; then
	docker_cmd="run  --rm  builder"
elif [ "${cmd}" = "build" ]; then
	docker_cmd="run  --rm  builder  make  build-all  OUT=${OUT}"
elif [ "${cmd}" = "clean" ]; then
	docker  rmi  ironos-builder:latest
	docker  system  prune  --filter label=ironos-builder:latest  --force
	exit "${?}"
else
	usage
	exit 1
fi;

# change dir to project root dir & run constructed command

cd "${root_dir}" || exit 1
echo -e "\n====>>>> Firing up & starting container..."
if [ "${cmd}" = "shell" ]; then
echo -e "\t* type \"exit\" to end the session when done;"
fi;
echo -e "\t* type \"${0} clean\" to delete created container (but not cached data)"
echo -e "\n====>>>> ${docker_app}  ${docker_file}  ${docker_cmd}\n"
eval "${docker_app}  ${docker_file}  ${docker_cmd}"
exit "${?}"
