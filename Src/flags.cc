// Define Abseil flags in a dedicated translation unit to avoid mixing
// Abseil headers with module imports in the main translation unit. This
// keeps includes that pull in Abseil implementation details out of files
// that import C++ modules which some compilers (clang-cl) can mishandle.
#include "absl/flags/flag.h"
#include "absl/flags/parse.h"
#include "absl/flags/usage.h"

#include <cstdint>
#include <string>

// Flag definitions
ABSL_FLAG(std::string, input, "", "Path to the input file");
ABSL_FLAG(std::string, output, "out", "Path to the output file");
ABSL_FLAG(int32_t, threads, 4, "Number of worker threads");
ABSL_FLAG(bool, verbose, false, "Enable verbose logging");

namespace kataglyphis {

void parse_flags(int argc, char** argv)
{
    absl::SetProgramUsageMessage("Usage: kataglyphis --input=FILE [options]");
    // Parse and ignore leftover positional arguments here.
    (void)absl::ParseCommandLine(argc, argv);
}

} // namespace kataglyphis

// Provide a C-linkage wrapper so the module-based main can reliably call the
// flag parsing function without depending on C++ name mangling or module
// visibility rules across translation units.
extern "C" void kataglyphis_parse_flags(int argc, char** argv)
{
    kataglyphis::parse_flags(argc, argv);
}
