from conan import ConanFile

class NativeServiceConan(ConanFile):
    name = "native_service"
    version = "1.0"
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeDeps", "CMakeToolchain"

    def requirements(self):
        self.requires("fmt/10.2.1")

    def layout(self):
        self.folders.build = "build"
