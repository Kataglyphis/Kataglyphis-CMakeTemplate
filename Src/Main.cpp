import kataglyphis_core;

// NOLINTBEGIN(misc-use-internal-linkage,cppcoreguidelines-avoid-non-const-global-variables,modernize-use-trailing-return-type)
// Declaration of the C-linkage wrapper implemented in Src/flags.cc. Placing
// the declaration at global scope avoids declaring `main` with extern "C"
// linkage (which triggers a warning) and avoids putting linkage-specifiers
// inside the function body which can confuse some frontends.
extern "C" void kataglyphis_parse_flags(int argc, char** argv);

int main(int argc, char** argv)
{
    // Parse flags in a separate translation unit to avoid including Abseil
    // headers in a module-importing TU. The parse_flags function is defined
    // in Src/flags.cc and will call absl::ParseCommandLine.
    kataglyphis_parse_flags(argc, argv);

    return kataglyphis::run();
}
// NOLINTEND(misc-use-internal-linkage,cppcoreguidelines-avoid-non-const-global-variables,modernize-use-trailing-return-type)
