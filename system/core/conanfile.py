from conan import ConanFile

class NativeService(ConanFile):
    name = "native_service"
    version = "0.1"
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeDeps", "CMakeToolchain"

    def requirements(self):
        # Dependencies can be added here
        pass
