module;

#include <string_view>

export module kataglyphis.config;

export namespace kataglyphis::config {
inline constexpr std::string_view renderer_version_major{"0"};
inline constexpr std::string_view renderer_version_minor{"0"};

inline constexpr std::string_view vulkan_version_major{""};
inline constexpr std::string_view vulkan_version_minor{""};
}
