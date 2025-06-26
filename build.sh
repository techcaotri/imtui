#!/bin/bash

set -e # Exit on any error

# Build configuration defaults
BUILD_TYPE="Release"
PARALLEL_JOBS=$(nproc)
CLEAN_BUILD=false
INSTALL_BUILD=false
RUN_TESTS=false
VERBOSE_BUILD=false
SETUP_ENV=false
BUILD_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
print_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

print_header() {
	echo -e "${CYAN}[BUILD]${NC} $1"
}

# Help function
show_help() {
	cat <<EOF
ImTui Build Script

USAGE:
    ./build.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --debug         Build in Debug mode (default: Release)
    -r, --release       Build in Release mode
    -c, --clean         Clean build directory before building
    -i, --install       Install after successful build
    -t, --test          Run tests after build
    -j, --jobs N        Number of parallel jobs (default: $PARALLEL_JOBS)
    -v, --verbose       Verbose build output

EXAMPLES:
    ./build.sh                    # Build in Release mode
    ./build.sh -d                 # Build in Debug mode
    ./build.sh -c -r              # Clean and build Release
    ./build.sh -d -j 8 -v         # Debug build with 8 jobs, verbose
    ./build.sh -j8                # Release build with 8 jobs (attached format)
    ./build.sh -c -i              # Clean, build, and install
    ./build.sh -d -t              # Debug build and run tests
    ./build.sh -cdrv              # Combined short options: clean, debug, release, verbose

BUILD DIRECTORIES:
    Release builds: ./build-release/
    Debug builds:   ./build-debug/

DEPENDENCIES:
    - CMake 3.15+
    - GCC/Clang with C++17 support

EOF
}

# Parse command line arguments with proper short option support
parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		# Long options
		--help)
			show_help
			exit 0
			;;
		--debug)
			BUILD_TYPE="Debug"
			shift
			;;
		--release)
			BUILD_TYPE="Release"
			shift
			;;
		--clean)
			CLEAN_BUILD=true
			shift
			;;
		--install)
			INSTALL_BUILD=true
			shift
			;;
		--test)
			RUN_TESTS=true
			shift
			;;
		--jobs)
			if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
				PARALLEL_JOBS="$2"
				shift 2
			else
				print_error "Option --jobs requires a numeric argument"
				echo "Usage: --jobs N (where N is number of parallel jobs)"
				exit 1
			fi
			;;
		--verbose)
			VERBOSE_BUILD=true
			shift
			;;
		--setup)
			SETUP_ENV=true
			shift
			;;
		# Short options (single character)
		-h)
			show_help
			exit 0
			;;
		-d)
			BUILD_TYPE="Debug"
			shift
			;;
		-r)
			BUILD_TYPE="Release"
			shift
			;;
		-c)
			CLEAN_BUILD=true
			shift
			;;
		-i)
			INSTALL_BUILD=true
			shift
			;;
		-t)
			RUN_TESTS=true
			shift
			;;
		-j)
			if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
				PARALLEL_JOBS="$2"
				shift 2
			else
				print_error "Option -j requires a numeric argument"
				echo "Usage: -j N (where N is number of parallel jobs)"
				exit 1
			fi
			;;
		-v)
			VERBOSE_BUILD=true
			shift
			;;
		# Combined short options (like -cdr) and attached -j options (like -j8)
		-*)
			option="$1"
			shift
			i=1
			while [[ $i -lt ${#option} ]]; do
				char="${option:$i:1}"
				case $char in
				h)
					show_help
					exit 0
					;;
				d)
					BUILD_TYPE="Debug"
					;;
				r)
					BUILD_TYPE="Release"
					;;
				c)
					CLEAN_BUILD=true
					;;
				i)
					INSTALL_BUILD=true
					;;
				t)
					RUN_TESTS=true
					;;
				j)
					# Handle attached -j format like -j8
					if [[ $i -eq $((${#option} - 1)) ]]; then
						# -j is at the end, next argument should be the number
						if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
							PARALLEL_JOBS="$1"
							shift
						else
							print_error "Option -j requires a numeric argument"
							exit 1
						fi
					else
						# Extract number from attached format like -j8
						num="${option:$((i + 1))}"
						if [[ "$num" =~ ^[0-9]+$ ]]; then
							PARALLEL_JOBS="$num"
							break # Exit the character loop since we processed the number
						else
							print_error "Invalid number format in -j option: $num"
							exit 1
						fi
					fi
					;;
				v)
					VERBOSE_BUILD=true
					;;
				*)
					print_error "Unknown short option: -$char"
					echo "Use -h or --help for usage information"
					exit 1
					;;
				esac
				((i++))
			done
			;;
		*)
			print_error "Unknown argument: $1"
			echo "Use -h or --help for usage information"
			exit 1
			;;
		esac
	done
}

# Set build directory based on build type
set_build_directory() {
	if [ "$BUILD_TYPE" = "Debug" ]; then
		BUILD_DIR="build-debug"
	else
		BUILD_DIR="build-release"
	fi
}

# Setup development environment
setup_development_environment() {
	print_header "Setting up development environment..."
  git submodule update --init --recursive
	print_success "Development environment setup complete"
}

# Clean build directory
clean_build_directory() {
	if [ -d "$BUILD_DIR" ]; then
		print_info "Cleaning build directory: $BUILD_DIR"
		rm -rf "$BUILD_DIR"
		print_success "Build directory cleaned"
	else
		print_info "Build directory $BUILD_DIR does not exist, skipping clean"
	fi
}

# Check dependencies
check_dependencies() {
	print_header "Checking build dependencies..."

	# Check for required tools
	local missing_deps=()

	if ! command -v cmake &>/dev/null; then
		missing_deps+=("cmake")
	fi

	if ! command -v pkg-config &>/dev/null; then
		missing_deps+=("pkg-config")
	fi

	# Check for ncurses
	if ! pkg-config --exists ncurses; then
		missing_deps+=("libncurses-dev")
	fi

	if [ ${#missing_deps[@]} -ne 0 ]; then
		print_error "Missing dependencies: ${missing_deps[*]}"
		print_info "Install with: sudo apt-get install ${missing_deps[*]}"
		exit 1
	fi

	print_success "All dependencies satisfied"
}

# Build configuration
configure_build() {
	print_header "Configuring $BUILD_TYPE build..."

	mkdir -p "$BUILD_DIR"
	cd "$BUILD_DIR"
  ln -sf "$BUILD_DIR" ../build

	local cmake_args="-DCMAKE_BUILD_TYPE=$BUILD_TYPE"

	if [ "$VERBOSE_BUILD" = true ]; then
		cmake_args="$cmake_args -DCMAKE_VERBOSE_MAKEFILE=ON"
	fi

	print_info "CMake arguments: $cmake_args"
	cmake .. $cmake_args

	cd ..
	print_success "Configuration complete"
}

# Build the project
build_project() {
	print_header "Building project in $BUILD_TYPE mode..."

	cd "$BUILD_DIR"

	local make_args="-j$PARALLEL_JOBS"
	if [ "$VERBOSE_BUILD" = true ]; then
		make_args="$make_args VERBOSE=1"
	fi

	print_info "Building with $PARALLEL_JOBS parallel jobs..."
	make $make_args

	cd ..
	print_success "Build completed successfully"
}

# Install the project
install_project() {
	print_header "Installing project..."

	cd "$BUILD_DIR"
	sudo make install
	cd ..

	print_success "Installation completed"
}

# Run tests
run_tests() {
	print_header "Running tests..."

	cd "$BUILD_DIR"
	if [ -f "Makefile" ] && make -n test &>/dev/null; then
		make test
		print_success "All tests passed"
	else
		print_warning "No tests found or test target not available"
	fi
	cd ..
}

# Main execution flow
main() {
	# Parse command line arguments
	parse_arguments "$@"

	# Set build directory
	set_build_directory

	print_header "ImTui Build System"
	print_info "Build Type: $BUILD_TYPE"
	print_info "Build Directory: $BUILD_DIR"
	print_info "Parallel Jobs: $PARALLEL_JOBS"
	print_info "Options: Clean=$CLEAN_BUILD, Install=$INSTALL_BUILD, Test=$RUN_TESTS, Verbose=$VERBOSE_BUILD"
	echo

	# Setup environment if requested
	if [ "$SETUP_ENV" = true ]; then
		setup_development_environment
		return 0
	fi

	# Check dependencies
	check_dependencies

	# Clean if requested
	if [ "$CLEAN_BUILD" = true ]; then
		clean_build_directory
	fi

	# Configure and build
	configure_build
	build_project

	# Install if requested
	if [ "$INSTALL_BUILD" = true ]; then
		install_project
	fi

	# Run tests if requested
	if [ "$RUN_TESTS" = true ]; then
		run_tests
	fi

	# Show completion message
	echo
	print_success "Build process completed successfully!"
	echo
}

# Execute main function
main "$@"
