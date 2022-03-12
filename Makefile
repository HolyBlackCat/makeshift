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
override proj_dir := $(patsubst ./,.,$(dir $(firstword $(MAKEFILE_LIST))))

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

# A recursive wildcard function.
# Source: https://stackoverflow.com/a/18258352/2752075
# Recursively searches a directory for all files matching a pattern.
# The first parameter is a directory, the second is a pattern.
# Example usage: SOURCES = $(call rwildcard, src, *.c *.cpp)
# This implementation differs from the original. It was changed to correctly handle directory names without trailing `/`, and several directories at once.
override rwildcard = $(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

# Writes $1 to the output, immediately. Similar to $(info), but not delayed until the end of the recipe, when output grouping is used.
override log_now = $(if $(filter-out true,$(MAKE_TERMOUT)),$(file >$(MAKE_TERMOUT),$1),$(info $1))


# --- Archive support ---

# We need it so early, because `archive_basename` is needed in the config files, and it needs to see all the archive types.
# Also because it allows the configs to modify those settings.

# Given archive filename $1, tries to determine the archive type. Returns one of `archive_types`, or empty on failure.
override archive_classify_filename = $(firstword $(foreach x,$(archive_types),$(if $(call archive_is-$x,$1),$x)))

# Given archive filename $1, returns the filename without the extension. Can work with lists.
# Essentially this removes extensions one by one, until it stops looking like an archive.
override archive_basename = $(foreach x,$1,$(if $(call archive_classify_filename,$x),$(call archive_basename,$(basename $x)),$x))

archive_types :=

# Archive type definitions:

# `archive_is-<type>` - given filename $1, should expand to a non-empty string if it's an archive of this type.
# `archive_extract-<type>` - should extract archive $1 to directory $2, and expand to nothing.

archive_types += TAR
override archive_is-TAR = $(or $(findstring .tar.,$1),$(filter %.tar,$1))
override archive_extract-TAR = $(call safe_shell_exec,tar -xf $(call quote,$1) -C $(call quote,$2))

archive_types += ZIP
override archive_is-ZIP = $(filter %.zip,$1)
override archive_extract-ZIP = $(call safe_shell_exec,unzip $(call quote,$1) -d $(call quote,$2))


# --- Language definitions ---

language_list :=

# Given filename $1, tries to guess the language. Causes an error on failure.
override guess_lang_from_filename = $(call guess_lang_from_filename_low,$1,$(firstword $(foreach x,$(language_list),$(if $(filter $(subst *,%,$(language_pattern-$x)),$1),$x))))
override guess_lang_from_filename_low = $(if $2,$2,$(error Unable to guess language from filename: $1))

# Everything should be mostly self-explanatory.
# `language_outputs_deps` describes whether an extra `.d` file is created or not (don't define it if not).
# In `language_command`:
# $1 is the input file.
# $2 is the output file.
# $3 is the project name.

language_list += c
override language_name-c := C
override language_pattern-c := *.c
override language_command-c = $(CC) -MMD -MP -c $1 -o $2 $(call lib_cache_flags,lib_cflags,$(__projsetting_libs_$3)) $(CFLAGS) $(__projsetting_common_flags_$3) $(__projsetting_cflags_$3)
override language_outputs_deps-c = y

language_list += cpp
override language_name-cpp := C++
override language_pattern-cpp := *.cpp
override language_command-cpp = $(CXX) -MMD -MP -c $1 -o $2 $(call lib_cache_flags,lib_cflags,$(__projsetting_libs_$3)) $(CXXFLAGS) $(__projsetting_common_flags_$3) $(__projsetting_cxxflags_$3)
override language_outputs_deps-cpp = y

language_list += rc
override language_name-rc := Resource
override language_pattern-rc := *.rc
override language_command-rc = $(WINDRES) $(WINDRES_FLAGS) -i $1 -o $2


# --- Define public config functions ---

# Only the ones starting with uppercase letters are actually public.

# List of library archives.
override lib_ar_list :=
# $1 is an archive name, or a space-separated list of them.
# A list is not recommended, because LibrarySetting always applies only to the last library.
override Library = $(call var,lib_ar_list += $1)

override lib_setting_names := deps build_system cmake_flags configure_vars
# On success, assigns $2 to variable `__libsetting_$1_<lib>`. Otherwise causes an error.
# Settings are:
# * deps - library dependencies, that this library will be allowed to see when building. A space-separated list of library names (their archive names without extensions).
# * build_system - override build system detection. Can be: `cmake`, `configure_make`, etc. See `id_build_system` below for the full list.
# * cmake_flags - if CMake is used, those are passed to it. Probably should be a list of `-D<var>=<value>`.
# * configure_vars - if configure+make is used, this is prepended to `configure` and `make`. This should be a list of `<var>=<value>`, but you could use `/bin/env` there too.
override LibrarySetting = \
	$(if $(filter-out $(lib_setting_names),$1)$(filter-out 1,$(words $1)),$(error Invalid library setting `$1`, expected one of: $(lib_setting_names)))\
	$(if $(filter 0,$(words $(lib_ar_list))),$(error Must specify library settings after a library))\
	$(call var,__libsetting_$(strip $1)_$(call archive_basename,$(lastword $(lib_ar_list))) := $2)

# List of projects.
override proj_list :=
# Allowed project types.
override proj_kind_names := exe shared

# $1 is the project kind, one of `proj_kind_names`.
# $2 is the project name, or a space-separated list of them.
# A list is not recommended, because ProjectSetting always applies only to the last library.
override Project = \
	$(if $(or $(filter-out $(proj_kind_names),$1),$(filter-out 1,$(words $1))),$(error Project kind must be one of: $(proj_kind_names)))\
	$(call var,proj_list += $2)\
	$(call var,__proj_kind_$(strip $2) := $(strip $1))\

override proj_setting_names := kind sources source_dirs cflags cxxflags ldflags common_flags flags_func libs linker_var

# On success, assigns $2 to variable `__projsetting_$1_<lib>`. Otherwise causes an error.
# Settings are:
# * kind - either `exe` or `shared`.
# * sources - individual source files.
# * source_dirs - directories to search for source files. The result is combined with `sources`.
# * {c,cxx}flags - compiler flags for C and CXX respectively.
# * ldflags - linker flags.
# * common_flags - those are added to both `{c,cxx}flags` and `ldflags`.
# * flags_func - a function name to determine extra per-file flags. The function is given the source filename as $1, and can return flags if it wants to.
# * libs - a space-separated list of libraries created with $(Library), or `*` to use all libraries.
# * linker_var - either CC or CXX. Defaults to CXX. Can also be any other variable.
override ProjectSetting = \
	$(if $(filter-out $(proj_setting_names),$1)$(filter-out 1,$(words $1)),$(error Invalid project setting `$1`, expected one of: $(proj_setting_names)))\
	$(if $(filter 0,$(words $(proj_list))),$(error Must specify project settings after a project))\
	$(call var,__projsetting_$(strip $1)_$(lastword $(proj_list)) := $2)


# --- Set default values before loading configs ---

# Detect target OS.
# Quasi-MSYS2 sets this variable...
ifeq ($(TARGET_OS),)
ifeq ($(OS),Windows_NT)
TARGET_OS := windows
else
TARGET_OS := linux
endif
endif

# Detect host OS.
# I had two options: `uname` and `uname -o`. The first prints `Linux` and `$(MSYSTEM)-some-junk`, and the second prints `GNU/Linux` and `Msys` on Linux and MSYS2 respectively.
# I don't want to parse MSYSTEM, so I decided to use `uname -o`.
ifneq ($(findstring Msys,$(call safe_shell_exec,uname -o)),)
HOST_OS := windows
else
HOST_OS := linux
endif

# Configure output extensions/prefixes.
PREFIX_exe :=
PREFIX_shared := lib
ifeq ($(TARGET_OS),windows)
EXT_exe := .exe
EXT_shared := .dll
else
EXT_exe :=
EXT_shared := .so
endif

# Traditional variables:
export CC ?=
export CXX ?=
export CPP ?=
export LD ?=
export CFLAGS :=
export CXXFLAGS :=
export CPPFLAGS :=
export LDFLAGS :=

# Windres settings:
WINDRES := windres
WINDRES_FLAGS := -O res

# Prevent pkg-config from finding external packages.
override PKG_CONFIG_PATH :=
export PKG_CONFIG_PATH
override PKG_CONFIG_LIBDIR :=
export PKG_CONFIG_LIBDIR

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
ifneq ($(MAKE_TERMERR),)
COMMON_FLAGS_IMPLICIT += -fdiagnostics-color=always# -Otarget messes with the colors, so we fix it here.
endif

# Libraries are built here.
LIB_DIR := $(proj_dir)/built_libs
# Library archives are found here.
ARCHIVE_DIR := $(proj_dir)/libs
# Object files are written here.
OBJ_DIR := $(proj_dir)/obj
# Binaries are written here.
BIN_DIR := $(proj_dir)/bin


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
# Note that we disable the detection when running with `-n`, since the shell function is also disabled in that case.
override find_versioned_tool = $(if $(findstring n,$(single_letter_makeflags)),$1,$(call find_versioned_tool_low,$1,$(lastword $(sort $(call safe_shell,bash -c 'compgen -c $1' | grep -Ex '$(subst +,\+,$1)(-[0-9]+)?')))))
override find_versioned_tool_low = $(if $2,$2,$(error Can't find $1))

ifeq ($(CC),)
override CC := $(call find_versioned_tool,clang)
endif
ifeq ($(CXX),)
override CXX := $(call find_versioned_tool,clang++)
endif
ifeq ($(LINKER),)
override LINKER := $(call find_versioned_tool,lld)
endif
endif


# --- Load project file ---
P := project.mk
include $P


# --- Finalize config ---

# Note that we can't add the flags to CC, CXX.
# It initially looked like we can, if we then do `-DCMAKE_C_COMPILER=$(subst $(space,;,$(CC))`, but CMake seems to ignore those extra flags. What a shame.
# Note that we can't use `+=` here, because if user overrides those variables, they may not be `:=`, and we then undefine `COMMON_FLAGS`.
override CFLAGS   := $(COMMON_FLAGS) $(CFLAGS)
override CFLAGS   := $(COMMON_FLAGS_IMPLICIT) $(CFLAGS)
override CXXFLAGS := $(COMMON_FLAGS) $(CXXFLAGS)
override CXXFLAGS := $(COMMON_FLAGS_IMPLICIT) $(CXXFLAGS)
override LDFLAGS  := $(COMMON_FLAGS) $(LDFLAGS)
override LDFLAGS  := $(COMMON_FLAGS_IMPLICIT) $(LDFLAGS)
override undefine COMMON_FLAGS
override undefine COMMON_FLAGS_IMPLICIT

override LDFLAGS := $(if $(LINKER),-fuse-ld=$(LINKER)) $(LDFLAGS)

ifeq ($(MODE),)
MODE := generic
endif

# Use this string in paths to mode-specific files.
override os_mode_string := $(TARGET_OS)/$(MODE)

# The list of library names.
override all_libs := $(call archive_basename,$(lib_ar_list))


# --- Print header ---

ifeq ($(TARGET_OS),$(HOST_OS))
$(info [Env] $(TARGET_OS), $(MODE))
else
$(info [Env] $(HOST_OS)->$(TARGET_OS), $(MODE))
endif


# --- Generate library targets based on config ---

# $1 is a directory, uses its contents to identify the build system.
# Returns empty string on failure, or one of the names from `buildsystem_detection` variables on success.
override id_build_system = $(word 2,$(subst ->, ,$(firstword $(filter $(patsubst $1/%,%->%,$(wildcard $1/*)),$(buildsystem_detection)))))

# Given library name $1, returns the log path for it. Can work with lists.
override lib_name_to_log_path = $(patsubst %,$(LIB_DIR)/%/$(os_mode_string)/log.txt,$1)
# Given library name $1, returns the installation prefix for it. Can work with lists.
override lib_name_to_prefix = $(patsubst %,$(LIB_DIR)/%/$(os_mode_string)/prefix,$1)

# Code for a library target.
# $1 is an archive name.
override define codesnippet_library =
# __ar_name = Archive filename
$(call var,__lib_name := $(call archive_basename,$(__ar_name)))# Library name
$(call var,__ar_path := $(ARCHIVE_DIR)/$(__ar_name))# Archive path
$(call var,__log_path_final := $(call lib_name_to_log_path,$(__lib_name)))# The final log path
$(call var,__log_path := $(__log_path_final).unfinished)# Temporary log path for an unfinished log

$(call, Forward the same variables to the target.)
$(__log_path_final): override __ar_name := $(__ar_name)
$(__log_path_final): override __lib_name := $(__lib_name)
$(__log_path_final): override __ar_path := $(__ar_path)
$(__log_path_final): override __log_path_final := $(__log_path_final)
$(__log_path_final): override __log_path := $(__log_path)

# NOTE: If adding any useful variable here, document then in `Variables available to build systems` below.

# Builds the library.
.PHONY: lib-$(__lib_name)
lib-$(__lib_name): $(__log_path_final)

# Cleans the library for this mode.
# `safe_shell_exec` is used here and everywhere to make sure those targets can't run in parallel with building the libraries.
.PHONY: clean-$(__lib_name)-this-mode
clean-$(__lib_name)-this-mode: override __lib_name := $(__lib_name)
clean-$(__lib_name)-this-mode:
	$(call safe_shell_exec,rm -rf $(call quote,$(LIB_DIR)/$(__lib_name)/$(os_mode_string)))
	@true

.PHONY: clean-$(__lib_name)-all
clean-$(__lib_name)-all: override __lib_name := $(__lib_name)
clean-$(__lib_name)-all:
	$(call safe_shell_exec,rm -rf $(call quote,$(LIB_DIR)/$(__lib_name)))
	@true

# Actually builds the library. Has a pretty alias, defined above.
$(__log_path_final): $(__ar_path) $(call lib_name_to_log_path,$(__libsetting_deps_$(__lib_name)))
	$(call, Firstly, detect archive type, and stop if unknown, to avoid creating junk.)
	$(call var,__ar_type := $(call archive_classify_filename,$(__ar_name)))
	$(if $(__ar_type),,$(error Don't know this archive extension))
	$(call var,__source_dir := $(LIB_DIR)/$(__lib_name)/$(os_mode_string)/source)
	$(call, We first extract the archive to this dir, then move the most nested subdir to __source_dir and delete this one.)
	$(call var,__tmp_source_dir := $(LIB_DIR)/$(__lib_name)/$(os_mode_string)/temp_source)
	$(call var,__build_dir := $(LIB_DIR)/$(__lib_name)/$(os_mode_string)/build)
	$(call var,__install_dir := $(call lib_name_to_prefix,$(__lib_name)))
	$(call log_now,[Library] $(__lib_name))
	$(call, Remove old files.)
	$(call safe_shell_exec,rm -rf $(call quote,$(__source_dir)))
	$(call safe_shell_exec,rm -rf $(call quote,$(__tmp_source_dir)))
	$(call safe_shell_exec,rm -rf $(call quote,$(__build_dir)))
	$(call safe_shell_exec,rm -rf $(call quote,$(__install_dir)))
	$(call safe_shell_exec,rm -f $(call quote,$(__log_path_final)))
	$(call safe_shell_exec,rm -f $(call quote,$(__log_path)))
	$(call, Make some directories.)
	$(call safe_shell_exec,mkdir -p $(call quote,$(__tmp_source_dir)))
	$(call safe_shell_exec,mkdir -p $(call quote,$(__build_dir)))
	$(call safe_shell_exec,mkdir -p $(call quote,$(__install_dir)))
	$(call safe_shell_exec,mkdir -p $(call quote,$(dir $(__log_path_final))))
	$(call log_now,[Library] >>> Extracting $(__ar_type) archive...)
	$(call archive_extract-$(__ar_type),$(__ar_path),$(__tmp_source_dir))
	$(call, Move the most-nested source dir to the proper location, then remove the remaining junk.)
	$(call safe_shell_exec,mv $(call quote,$(call most_nested,$(__tmp_source_dir))) $(call quote,$(__source_dir)))
	$(call safe_shell_exec,rm -rf $(call quote,$(__tmp_source_dir)))
	$(call, Detect build system.)
	$(call var,__build_sys := $(strip $(if $(__libsetting_build_system_$(__lib_name)),\
		$(__libsetting_build_system_$(__lib_name)),\
		$(call id_build_system,$(__source_dir)))\
	))
	$(if $(filter undefined,$(origin buildsystem-$(__build_sys))),$(error Don't know this build system: `$(__build_sys)`))
	$(call, Run the build system.)
	$(buildsystem-$(__build_sys))
	$(call, On success, move the log to the right location.)
	$(call safe_shell_exec,mv $(call quote,$(__log_path)) $(call quote,$(__log_path_final)))
	$(call log_now,[Library] >>> Done)
	@true
endef

# Generate the targets for each library.
$(foreach x,$(lib_ar_list),$(call var,__ar_name := $x)$(eval $(value codesnippet_library)))

.PHONY: libs
libs: $(addprefix lib-,$(all_libs))

# Destroy build/install results for all known libraries.
.PHONY: clean-libs-known
clean-libs-known:
	$(foreach x,$(all_libs),$(call safe_shell_exec,rm -rf $(call quote,$(LIB_DIR)/$x)))
	@true

# Destroy build/install results for all libraries in the directory, even unknown ones.
.PHONY: clean-libs-all
clean-libs-all:
	$(call safe_shell_exec,rm -rf $(call quote,$(LIB_DIR)))
	@true

# Functions to get library flags:

# Expands to `pkg-config` with the proper config variables.
# Not a function.
override lib_invoke_pkgconfig = PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR=$(call quote,$(subst $(space),:,$(foreach x,$(all_libs),$(LIB_DIR)/$x/$(os_mode_string)/prefix/lib/pkgconfig))) pkg-config --define-prefix

# Given list of library names `$1`, returns the pkg-config packages for them.
override lib_find_packages_for = $(basename $(notdir $(wildcard $(foreach x,$1,$(LIB_DIR)/$x/$(os_mode_string)/prefix/lib/pkgconfig/*.pc))))

# Determine cflags for a list of libraries `$1`.
# We just run pkg-config on all packages of those libraries.
override lib_cflags = $(strip\
	$(if $(filter-out $(all_libs),$1),$(error Unknown libraries: $(filter-out $(all_libs),$1)))\
	$(call, Raw flags will be written here.)\
	$(call var,__raw_flags :=)\
	$(call, Pkg-config packages will be written here.)\
	$(call var,__pkgs :=)\
	$(call, Run lib_cflags_low for every library.)\
	$(foreach x,$1,$(call lib_cflags_low,$(call lib_find_packages_for,$x)))\
	$(call, Run pkg-config for libraries that have pkg-config packages.)\
	$(if $(__pkgs),$(call safe_shell,$(lib_invoke_pkgconfig) --cflags $(__pkgs)))\
	$(__raw_flags)\
	)
override lib_cflags_low = \
	$(if $1,\
		$(call, Have pkg-config file, so add this lib to the list of packages.)\
		$(call var,__pkgs += $1)\
	,\
		$(call, Use a hardcoded search path.)\
		$(call var,__raw_flags += -I$(LIB_DIR)/$x/$(os_mode_string)/prefix/include)\
	)

# Library filename patterns, used by `lib_ldflags` below.
override lib_file_patterns := lib%.so lib%.a

# Determine ldflags for a list of libraries `$1`.
# We try to run pkg-config for each library if available, falling back to manually finding the libraries and linking them.
override lib_ldflags = $(strip\
	$(if $(filter-out $(all_libs),$1),$(error Unknown libraries: $(filter-out $(all_libs),$1)))\
	$(call, Raw flags will be written here.)\
	$(call var,__raw_flags :=)\
	$(call, Pkg-config packages will be written here.)\
	$(call var,__pkgs :=)\
	$(call, Run lib_ldflags_low for every library.)\
	$(foreach x,$1,$(call lib_ldflags_low,$(call lib_find_packages_for,$x)))\
	$(call, Run pkg-config for libraries that have pkg-config packages.)\
	$(if $(__pkgs),$(call safe_shell,$(lib_invoke_pkgconfig) --libs $(__pkgs)))\
	$(__raw_flags)\
	)
override lib_ldflags_low = \
	$(if $1,\
		$(call, Have pkg-config file, so add this lib to the list of packages.)\
		$(call var,__pkgs += $1)\
	,\
		$(call, Dir for library search.)\
		$(call var,__dir := $(LIB_DIR)/$x/$(os_mode_string)/prefix/lib)\
		$(call, Find library filenames.)\
		$(call var,__libs := $(notdir $(wildcard $(subst %,*,$(addprefix $(__dir)/,$(lib_file_patterns))))))\
		$(if $(__libs),\
			$(call, Strip prefix and extension.)\
			$(foreach x,$(lib_file_patterns),$(call var,__libs := $(patsubst $x,%,$(__libs))))\
			$(call, Convert to flags.)\
			$(call var,__raw_flags += -L$(__dir) $(addprefix -l,$(sort $(__libs))))\
		)\
	)

# $1 is `lib_{c,ld}flags`. $2 is a space-separated list of libraries.
# Calls $1($2) and maintains a global flag cache, to speed up repeated calls.
override lib_cache_flags = $(if $(strip $2),$(call lib_cache_flags_low,$1,$2,__cached_$1_$(subst $(space),@,$(strip $2))))
override lib_cache_flags_low = $(if $($3),,$(call var,$3 := $(call $1,$2)))$($(3))


# --- Generate code build targets based on config ---

# Find source files.
override source_file_patterns := $(foreach x,$(language_list),$(language_pattern-$x))
$(foreach x,$(proj_list),$(call var,__proj_allsources_$x := $(sort $(__projsetting_sources_$x) $(call rwildcard,$(__projsetting_source_dirs_$x),$(source_file_patterns)))))
override all_source_files := $(sort $(foreach x,$(proj_list),$(__proj_allsources_$x)))

# Given source filenames $1 and a project $2, returns the resulting dependency output files, if any. Some languages don't generate them.
override source_files_to_dep_outputs = $(strip $(foreach x,$1,$(if $(language_outputs_deps-$(call guess_lang_from_filename,$x)),$(OBJ_DIR)/$(os_mode_string)/$2/$x.d)))

# Given source filenames $1 and a project $2, returns the resulting primary output files. Never returns less elements than in $1.
# and returns only the first output for each file.
override source_files_to_main_outputs = $(patsubst %,$(OBJ_DIR)/$(os_mode_string)/$2/%.o,$1)

# Given source filenames $1 and a project $2, returns all outputs for them. Might return more elements than in $1, but never less.
# The first resulting element will always be the main output.
override source_files_to_output_list = $(call source_files_to_main_outputs,$1,$2) $(call source_files_to_dep_outputs,$1,$2)


# A list of targets that need directories to be created for them.
override targets_needing_dirs :=
# * The object files:
override targets_needing_dirs += $(foreach x,$(proj_list),$(call source_files_to_output_list,$(__proj_allsources_$x),$x))
# Generate the directory targets.
$(foreach x,$(targets_needing_dirs),$(eval $x: | $(dir $x)))
$(foreach x,$(sort $(dir $(targets_needing_dirs))),$(eval $x: ; @mkdir -p $(call quote,$x)))

# A template for object file targets.
# Input variables:
# `__src` - the source file.
# `__proj` - the project name.
override define codesnippet_object =
# Output filenames.
override __outputs := $(call source_files_to_output_list,$(__src),$(__proj))

$(__outputs) &: override __outputs := $(__outputs)
$(__outputs) &: override __proj := $(__proj)
$(__outputs) &: override __lang := $(call guess_lang_from_filename,$(__src))

$(__outputs): $(__src) $(call lib_name_to_log_path,$(all_libs))
	$(call log_now,[$(__proj)] [$(language_name-$(__lang))] $<)
	@$(call language_command-$(__lang),$<,$(firstword $(__outputs)),$(__proj)) $(call $(__projsetting_flags_func_$(__proj)),$<)
endef

# Generate object file targets.
$(foreach x,$(proj_list),$(call var,__proj := $x)$(foreach y,$(__proj_allsources_$x),$(call var,__src := $y)$(eval $(value codesnippet_object))))


override proj_kind = $(foreach x,$1,$())

override proj_output_filename = $(foreach )

# A template for link targets.
# The only input variable is `__proj`, the project name.
override define codesnippet_link =

override __filename :=  $(BIN_DIR)/$(os_mode_string)/$(PREFIX_$(__proj_kind_$(__proj)))$(__proj)$(EXT_$(__proj_kind_$(__proj)))

$(__outputs) &: override __proj := $(__proj)

$(__outputs): $(call source_files_to_main_outputs,$(__proj_allsources_$(__proj)))
	$(call log_now,[$(__proj)] [$(language_name-$(__lang))] $<)
	$(call var,__link := $(__projsetting_linker_var_$(__proj)))
	$(if $(__link),$(__link),$(CXX)) $(filter %.o,$^) $(LDFLAGS) $(__projsetting_ldflags_$(__proj))
endef
$(error finish the linking target)


.DEFAULT_GOAL := foo
foo: libs
	echo $$CC


# --- Build system definitions ---

# Variables available to build systems:
# __lib_name - library name.
# __log_path - the log file you should append to.
# __build_dir - the directory you should build in.
# __install_dir - the prefix you should install to.
# __source_dir - the source location. We automatically descend into subdirectories, if there is nothing else next to them.

# How to define a build system:
# * Create a variable named `buildsystem-<name>`, with a sequence of `$(call safe_shell_exec,)` commands, using the variables listed above.
# * If you want to, modify `buildsystem_detection` to auto-detect your build system.

# Modify this variable to tweak build system detection.
# Order matters, the first match is used.
# A space separated list of `<filename>-><buildsystem>`.
buildsystem_detection := CMakeLists.txt->cmake configure->configure_make


override buildsystem-cmake = \
	$(call log_now,[Library] >>> Configuring CMake...)\
	$(call safe_shell_exec,cmake\
		-S $(call quote,$(__source_dir))\
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
		-DCMAKE_SYSTEM_PREFIX_PATH=$(call quote,$(abspath $(__install_dir))$(subst $(space);,;,$(foreach x,$(call lib_name_to_prefix,$(__libsetting_deps_$(__lib_name))),;$(abspath $x))))\
		$(if $(CMAKE_GENERATOR),$(call quote,-G$(CMAKE_GENERATOR)))\
		$(__libsetting_cmake_flags_$(__lib_name))\
		>>$(call quote,$(__log_path))\
	)\
	$(call log_now,[Library] >>> Building...)\
	$(call safe_shell_exec,cmake --build $(call quote,$(__build_dir)) >>$(call quote,$(__log_path)) -j$(JOBS))\
	$(call log_now,[Library] >>> Installing...)\
	$(call safe_shell_exec,cmake --install $(call quote,$(__build_dir)) >>$(call quote,$(__log_path)))\

override buildsystem-configure_make = \
	$(call var,__bs_shell_vars := $(env_vars_for_shell) $(__libsetting_configure_vars_$(__lib_name)))\
	$(call, Since we can't configure multiple search prefixes, like we do with CMAKE_SYSTEM_PREFIX_PATH,)\
	$(call, we copy the prefixes of our dependencies to our own prefix.)\
	$(foreach x,$(call lib_name_to_prefix,$(__libsetting_deps_$(__lib_name))),$(call safe_shell_exec,cp -rT $(call quote,$x) $(call quote,$(__install_dir))))\
	$(call log_now,[Library] >>> Running `./configure`...)\
	$(call, Note abspath on the prefix, I got an error explicitly requesting an absolute path. Tested on libvorbis.)\
	$(call, Note the jank `cd`. It seems to allow out-of-tree builds.)\
	$(call safe_shell_exec,(cd $(call quote,$(__build_dir)) && $(__bs_shell_vars) $(call quote,$(abspath $(__source_dir)/configure)) --prefix=$(call quote,$(abspath $(__install_dir)))) >>$(call quote,$(__log_path)))\
	$(call log_now,[Library] >>> Building...)\
	$(call safe_shell_exec,$(__bs_shell_vars) make -C $(call quote,$(__build_dir)) -j$(JOBS) -Otarget >>$(call quote,$(__log_path)))\
	$(call log_now,[Library] >>> Installing...)\
	$(call, Note DESTDIR. We don't want to install to prefix yet, since we've copied our dependencies there.)\
	$(call, Note abspath for DESTDIR. You get an error otherwise, explicitly asking for an absolute one. Tested on libvorbis.)\
	$(call, Note redirecting stderr. Libtool warns when DESTDIR is non-empty, which is useless: "remember to run libtool --finish")\
	$(call safe_shell_exec,$(__bs_shell_vars) DESTDIR=$(call quote,$(abspath $(__source_dir)/__tmp_prefix)) make -C $(call quote,$(__build_dir)) install 2>&1 >>$(call quote,$(__log_path)))\
	$(call, Now we can clean the prefix. Can't do it before installing, because erasing headers from there would trigger a rebuild.)\
	$(call safe_shell_exec,rm -rf $(call quote,$(__install_dir)))\
	$(call, Move from the temporary prefix to the proper one. Note the janky abspath, which is needed because of how DESTDIR works.)\
	$(call safe_shell_exec,mv $(call quote,$(__source_dir)/__tmp_prefix/$(abspath $(__install_dir))) $(call quote,$(__install_dir)))\
	$(call safe_shell_exec,rm -rf $(call quote,$(__source_dir)/__tmp_prefix))\
