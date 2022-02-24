# --- Configure Make ---

# `rR` disables builtin variables and flags.
# `rR` doesn't properly disable built-in variables. They only disappear for recipes, but still exist for initial makefile parse.
# We manually unset them, except for a few useful ones.
$(foreach x,$(filter-out .% MAKE% SHELL CURDIR,$(.VARIABLES)) MAKEINFO,$(if $(filter default,$(origin $x)),$(eval override undefine $x)))

# `-Otarget` groups the output by recipe (manual says it's the default behavior, which doesn't seem to be the case.)
MAKEFLAGS += rR -Otarget

# Automatically parallelize.
JOBS := $(shell nproc)$(if $(filter-out 0,$(.SHELLSTATUS)),$(info Unable to determine the number of cores, will use one.)1)
MAKEFLAGS += -j$(JOBS)

# Prevent recursive invocations of Make from using our flags.
# This fixes some really obscure bugs.
unexport MAKEFLAGS

# Disable localized messages.
override LANG :=
export LANG


# --- Define contants ---

override define lf :=
$(call)
$(call)
endef

override space := $(call) $(call)

# The directory with the makefile.
override proj_dir := $(dir $(firstword $(MAKEFILE_LIST)))

# A string of all single-letter Make flags, without spaces.
override single_letter_makeflags = $(filter-out -%,$(firstword $(MAKEFLAGS)))


# --- Define functions ---

# Used to create local variables in a safer way. E.g. `$(call var,x := 42)`.
override var = $(eval override $(subst $,$$$$,$1))

# Encloses $1 in single quotes, with proper escaping for the shell.
# If you makefile uses single quotes everywhere, a decent way to transition is to manually search and replace `'(\$(?:.|\(.*?\)))'` with `$(call quote,$1)`.
override quote = '$(subst ','"'"',$1)'

ifneq ($(findstring n,$(single_letter_makeflags)),)
# See below.
override safe_shell = $(info Would run shell command: $1)
override shell_status = $(info Would check command status: $1)
else ifeq ($(filter --trace,$(MAKEFLAGS)),)
# Same as `$(shell ...)`, but triggers a error on failure.
override safe_shell = $(shell $1)$(if $(filter-out 0,$(.SHELLSTATUS)),$(error Unable to execute `$1`, exit code $(.SHELLSTATUS)))
# Same as `$(shell ...)`, expands to the shell status code rather than the command output.
override shell_status = $(call,$(shell $1))$(.SHELLSTATUS)
else
# Same functions but with logging.
override safe_shell = $(info Shell command: $1)$(shell $1)$(if $(filter-out 0,$(.SHELLSTATUS)),$(error Unable to execute `$1`, exit code $(.SHELLSTATUS)))
override shell_status = $(info Shell command: $1)$(call,$(shell $1))$(.SHELLSTATUS)$(info Exit code: $(.SHELLSTATUS))
endif

# Same as `safe_shell`, but discards the output and expands to nothing.
override safe_shell_exec = $(call,$(call safe_shell,$1))

# $1 is a directory. If it has a single subdirectory and nothing more, adds it to the path, recursively.
override most_nested = $(call most_nested_low,$1,$(filter-out $(most_nested_ignored_files),$(wildcard $1/*)))
override most_nested_low = $(if $(filter 1,$(words $2)),$(call most_nested,$2),$1)
# `most_nested` ignores those filenames.
override most_nested_ignored_files = pax_global_header


# --- Define public config functions ---

# Only the ones starting with uppercase letters are actually public.

# Given archive filename $1, returns the filename without the extension.
override archive_basename = $(patsubst %.tar,%,$(basename $1))

override lib_list :=
# $1 is an archive name, or a space-separated list of them.
override Library = $(call var,lib_list += $1)

override lib_setting_names := deps build_system cmake_flags configure_vars
# On success, assigns $2 to variable `_libsetting_$1_<lib>`. Otherwise causes an error.
# Settings are:
# * deps - library dependencies, that this library will be allowed to see when building. A space-separated list of library names (their archive names without extensions).
# * build_system - override build system detection. Can be: `cmake`, `configure_make`, etc. See `id_build_system` below for the full list.
# * cmake_flags - if CMake is used, those are passed to it. Probably should be a list of `-D<var>=<value>`.
# * configure_vars - if configure+make is used, this is prepended to `configure` and `make`. This should be a list of `<var>=<value>`, but you could use `/bin/env` there too.
override LibrarySetting = \
	$(if $(filter-out $(lib_setting_names),$1)$(filter-out 1,$(words $1)),$(error Invalid library setting: $1))\
	$(if $(filter 0,$(words $(lib_list))),$(error Must specify library settings after a library))\
	$(call var,_libsetting_$(strip $1)_$(call archive_basename,$(lastword $(lib_list))) := $2)


# --- Set default values before loading configs ---

# Traditional variables:
export CC :=
export CXX :=
export CPP :=
export LD :=
export CFLAGS :=
export CXXFLAGS :=
export CPPFLAGS :=
export LDFLAGS :=

# A list of those variables, and a string suitable to set them in a shell.
override exported_env_vars_list := CC CXX CPP LD CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
override env_vars_for_shell = $(foreach x,$(exported_env_vars_list),$x=$(call quote,$($x)))

MODE :=# Build mode.
CMAKE_GENERATOR :=# CMake generator, not quoted. Optional.
COMMON_FLAGS :=# Used both when compiling and linking.
LINKER :=# E.g. `lld` or `lld-13`. Can be empty to use the default one.

# Used both when compiling and linking. Those are set automatically.
# Note `=` instead of `:=`, since LINKER is set later.
COMMON_FLAGS_IMPLICIT = -fPIC
ifneq ($(and $(MAKE_TERMOUT),$(MAKE_TERMERR)),)
COMMON_FLAGS_IMPLICIT += -fdiagnostics-color=always# -Otarget messes with the colors, so we fix it here.
endif

# Libraries are built here.
LIB_DIR := $(proj_dir)/built_libs
# Library archives are found here.
ARCHIVE_DIR := $(proj_dir)/libs


# --- Load configs from current and parent directories ---

# The expected file name. In those files, use $(here) to get the location of the current file.
override config_filename := local_config.mk
override load_parent_configs = $(call load_parent_configs_low,$1,$2,$1/..,$(abspath $1/..))
override load_parent_configs_low = $(if $(findstring $2,$4),,$(call load_parent_configs,$3,$4))$(call var,here := $1)$(eval -include $1/$(config_filename))
$(call load_parent_configs,$(proj_dir),$(abspath $(proj_dir)))
override undefine here


# --- Fall back to default compiler if not specified ---

# Without this condition, the compiler detection messes with the tab completion for Make in the shell.
ifeq ($(findstring p,$(single_letter_makeflags)),)
# $1 is a clang tool name, e.g. `clang` or `clang++`.
# On success, returns the same tool, possibly suffixed with a version.
# Raises an error on failure.
override find_versioned_tool = $(call find_versioned_tool_low,$1,$(lastword $(sort $(call safe_shell,bash -c 'compgen -c $1' | grep -Ex '$(subst +,\+,$1)(-[0-9]+)?'))))
override find_versioned_tool_low = $(if $2,$2,$(error Can't find $1))

override guessed_tools_list :=
ifeq ($(CC),)
override CC := $(call find_versioned_tool,clang)
override guessed_tools_list += CC=$(CC)
endif
ifeq ($(CXX),)
override CXX := $(call find_versioned_tool,clang++)
override guessed_tools_list += CXX=$(CXX)
endif
ifeq ($(LINKER),)
override LINKER := $(call find_versioned_tool,lld)
override guessed_tools_list += LINKER=$(LINKER)
endif

$(if $(guessed_tools_list),$(info Guessed: $(guessed_tools_list)))
endif


# --- Load project file ---
P := project.mk
include $P


# --- Finalize config ---

# Note that we can't add the flags to CC, CXX.
# It initially looks like we can, if we then do `-DCMAKE_C_COMPILER=$(subst $(space,;,$(CC))`,
# but CMake seems to ignore those extra flags. What a shame.
override CFLAGS += $(COMMON_FLAGS)
override CFLAGS += $(COMMON_FLAGS_IMPLICIT)
override CXXFLAGS += $(COMMON_FLAGS)
override CXXFLAGS += $(COMMON_FLAGS_IMPLICIT)
override LDFLAGS += $(COMMON_FLAGS)
override LDFLAGS += $(COMMON_FLAGS_IMPLICIT)
override undefine COMMON_FLAGS
override undefine COMMON_FLAGS_IMPLICIT

override LDFLAGS += $(if $(LINKER),-fuse-ld=$(LINKER))

# The value of `$(MODE)`, if specified. Otherwise `generic`.
# Use this string in paths to mode-specific files.
override modestring := $(if $(MODE),$(MODE),generic)


# --- Generate library targets based on config ---

# Given filename $1, checks if it looks like a tar archive.
override archive_is_tar = $(or $(findstring .tar.,$1),$(filter %.tar,$1))
# Extracts tar archive $1 to path $2.
override extract_tar = $(call safe_shell_exec,tar -xf $(call quote,$1) -C $(call quote,$2))

# $1 is a directory, uses its contents to identify the build system.
# Can return: `cmake`, or an empty string.
override id_build_system = $(call var,__file_list := $(patsubst $1/%,%,$(wildcard $1/*)))\
	$(if $(filter CMakeLists.txt,$(__file_list)),cmake,\
	$(if $(filter configure,$(__file_list)),configure_make))

# Given library name $1, returns the log path for it. Can work with lists.
override lib_name_to_log_path = $(patsubst %,$(LIB_DIR)/%/$(modestring)/log.txt,$1)
# Given library name $1, returns the installation prefix for it. Can work with lists.
override lib_name_to_prefix = $(patsubst %,$(LIB_DIR)/%/$(modestring)/prefix,$1)

# Writes $1 to the output, immediately. If you use $(info) instead, it will be delayed until the end of the recipe.
override lib_log_now = $(if $(filter-out true,$(MAKE_TERMOUT)),$(file >$(MAKE_TERMOUT),$1),$(info $1))

# Code for a library target.
# $1 is an archive name.
# NOTE: Since we run everything from
override define code_library =
# __ar_name = Archive filename
$(call var,__lib_name := $(call archive_basename,$(__ar_name)))# Library name
$(call var,__ar_path := $(ARCHIVE_DIR)/$(__ar_name))# Archive path
$(call var,__log_path := $(call lib_name_to_log_path,$(__lib_name)))# Log path
$(call var,__log_path_tmp := $(__log_path).unfinished)# Temporary log path for an unfinished log

$(call, Forward the same variables to the target.)
$(__log_path): override __ar_name := $(__ar_name)
$(__log_path): override __lib_name := $(__lib_name)
$(__log_path): override __ar_path := $(__ar_path)
$(__log_path): override __log_path := $(__log_path)
$(__log_path): override __log_path_tmp := $(__log_path_tmp)

# Builds the library.
.PHONY: $(__lib_name)
$(__lib_name): $(__log_path)

# Cleans the library for this mode.
# `safe_shell_exec` is used here and everywhere to make sure those targets can't run in parallel with building the libraries.
.PHONY: clean-$(__lib_name)-this-mode
clean-$(__lib_name)-this-mode: override __lib_name := $(__lib_name)
clean-$(__lib_name)-this-mode:
	$(call safe_shell_exec,rm -rf $(call quote,$(LIB_DIR)/$(__lib_name)/$(modestring)))
	@true

.PHONY: clean-$(__lib_name)-all
clean-$(__lib_name)-all: override __lib_name := $(__lib_name)
clean-$(__lib_name)-all:
	$(call safe_shell_exec,rm -rf $(call quote,$(LIB_DIR)/$(__lib_name)))
	@true

# Actually builds the library. Has a pretty alias, defined above.
$(__log_path): $(__ar_path) $(call lib_name_to_log_path,$(_libsetting_deps_$(__lib_name)))
	$(call var,__source_dir := $(LIB_DIR)/$(__lib_name)/$(modestring)/source)
	$(call var,__build_dir := $(LIB_DIR)/$(__lib_name)/$(modestring)/build)
	$(call var,__install_dir := $(call lib_name_to_prefix,$(__lib_name)))
	$(call lib_log_now,[Library] $(__lib_name))
	$(call, Remove old files.)
	$(call safe_shell_exec,rm -rf $(call quote,$(__source_dir)))
	$(call safe_shell_exec,rm -rf $(call quote,$(__build_dir)))
	$(call safe_shell_exec,rm -rf $(call quote,$(__install_dir)))
	$(call safe_shell_exec,rm -f $(call quote,$(__log_path)))
	$(call safe_shell_exec,rm -f $(call quote,$(__log_path_tmp)))
	$(call, Make some directories.)
	$(call safe_shell_exec,mkdir -p $(call quote,$(__source_dir)))
	$(call safe_shell_exec,mkdir -p $(call quote,$(__build_dir)))
	$(call safe_shell_exec,mkdir -p $(call quote,$(__install_dir)))
	$(call safe_shell_exec,mkdir -p $(call quote,$(dir $(__log_path))))
	$(call, Extract archive.)
	$(if $(call archive_is_tar,$(__ar_name)),\
		$(call lib_log_now,[Library] >>> Extracting TAR archive...)\
		$(call extract_tar,$(__ar_path),$(__source_dir))\
	,$(error Don't know this archive extension)\
	)
	$(call var,__true_source_dir := $(call most_nested,$(__source_dir)))
	$(call var,__build_sys := $(if $(_libsetting_build_system_$(__lib_name)),\
		$(_libsetting_build_system_$(__lib_name)),\
		$(call id_build_system,$(__true_source_dir)))\
	)
	$(if $(filter cmake,$(__build_sys)),\
		$(call lib_log_now,[Library] >>> Configuring CMake...)\
		$(call safe_shell_exec,cmake\
			-S $(call quote,$(__true_source_dir))\
			-B $(call quote,$(__build_dir))\
			-Wno-dev\
			-DCMAKE_C_COMPILER=$(call quote,$(subst $(space),;,$(CC)))\
			-DCMAKE_CXX_COMPILER=$(call quote,$(subst $(space),;,$(CXX)))\
			-DCMAKE_C_FLAGS=$(call quote,$(CFLAGS))\
			-DCMAKE_CXX_FLAGS=$(call quote,$(CXXFLAGS))\
			-DCMAKE_EXE_LINKER_FLAGS=$(call quote,$(LDFLAGS))\
			-DCMAKE_MODULE_LINKER_FLAGS=$(call quote,$(LDFLAGS))\
			-DCMAKE_SHARED_LINKER_FLAGS=$(call quote,$(LDFLAGS))\
			$(call, Specifying an invalid build type disables built-in flags.)\
			-DCMAKE_BUILD_TYPE=Custom\
			-DCMAKE_INSTALL_PREFIX=$(call quote,$(__install_dir))\
			$(call, I'm not sure why abspath is needed here, but stuff doesn't work otherwise. Tested on libvorbis depending on libogg.)\
			$(call, Note the fancy logic that attempts to support spaces in paths.)\
			-DCMAKE_SYSTEM_PREFIX_PATH=$(call quote,$(abspath $(__install_dir))$(subst $(space);,;,$(foreach x,$(call lib_name_to_prefix,$(_libsetting_deps_$(__lib_name))),;$(abspath $x))))\
			$(if $(CMAKE_GENERATOR),$(call quote,-G$(CMAKE_GENERATOR)))\
			$(_libsetting_cmake_flags_$(__lib_name))\
			>>$(call quote,$(__log_path_tmp))\
		)\
		$(call lib_log_now,[Library] >>> Building...)\
		$(call safe_shell_exec,cmake --build $(call quote,$(__build_dir)) >>$(call quote,$(__log_path_tmp)) -j$(JOBS))\
		$(call lib_log_now,[Library] >>> Installing...)\
		$(call safe_shell_exec,cmake --install $(call quote,$(__build_dir)) >>$(call quote,$(__log_path_tmp)))\
	,$(if $(filter configure_make,$(__build_sys)),\
		$(call var,__shell_vars := $(env_vars_for_shell) $(_libsetting_configure_vars_$(__lib_name)))\
		$(call, Since we can't configure multiple search prefixes, like we do with CMAKE_SYSTEM_PREFIX_PATH,)\
		$(call, we copy the prefixes of our dependencies to our own prefix.)\
		$(foreach x,$(call lib_name_to_prefix,$(_libsetting_deps_$(__lib_name))),$(call safe_shell_exec,cp -rT $(call quote,$x) $(call quote,$(__install_dir))))\
		$(call lib_log_now,[Library] >>> Running `./configure`...)\
		$(call, Note abspath on the prefix, I got an error explicitly requesting an absolute path. Tested on libvorbis.)\
		$(call, Note the jank `cd`. It seems to allow out-of-tree builds.)\
		$(call safe_shell_exec,(cd $(call quote,$(__build_dir)) && $(__shell_vars) $(call quote,$(abspath $(__true_source_dir)/configure)) --prefix=$(call quote,$(abspath $(__install_dir)))) >>$(call quote,$(__log_path_tmp)))\
		$(call lib_log_now,[Library] >>> Building...)\
		$(call safe_shell_exec,$(__shell_vars) make -C $(call quote,$(__build_dir)) -j$(JOBS) -Otarget >>$(call quote,$(__log_path_tmp)))\
		$(call lib_log_now,[Library] >>> Installing...)\
		$(call, Note DESTDIR. We don't want to install to prefix yet, since we've copied our dependencies there.)\
		$(call, Note abspath for DESTDIR. You get an error otherwise, explicitly asking for an absolute one. Tested on libvorbis.)\
		$(call, Note redirecting stderr. Libtool warns when DESTDIR is non-empty, which is useless: "remember to run libtool --finish")\
		$(call safe_shell_exec,$(__shell_vars) DESTDIR=$(call quote,$(abspath $(__true_source_dir)/__tmp_prefix)) make -C $(call quote,$(__build_dir)) install 2>&1 >>$(call quote,$(__log_path_tmp)))\
		$(call, Now we can clean the prefix. Can't do it before installing, because erasing headers from there would trigger a rebuild.)\
		$(call safe_shell_exec,rm -rf $(call quote,$(__install_dir)))\
		$(call, Move from the temporary prefix to the proper one. Note the janky abspath, which is needed because of how DESTDIR works.)\
		$(call safe_shell_exec,mv $(call quote,$(__true_source_dir)/__tmp_prefix/$(abspath $(__install_dir))) $(call quote,$(__install_dir)))\
		$(call safe_shell_exec,rm -rf $(call quote,$(__true_source_dir)/__tmp_prefix))\
	,$(error Don't know this build system))\
	)

	$(call, On success, move the log to the right location.)
	$(call safe_shell_exec,mv $(call quote,$(__log_path_tmp)) $(call quote,$(__log_path)))
	$(call lib_log_now,[Library] >>> Done)\
	@true
endef

$(foreach x,$(lib_list),$(call var,__ar_name := $x)$(eval $(value code_library)))




.DEFAULT_GOAL := foo
foo:
	echo $$CC
