{ stdenv, fetch, cmake, libxml2, llvm, version, clang-tools-extra_src, python3, lld
, fixDarwinDylibNames
, enableManpages ? false
, enablePolly ? false # TODO: get this info from llvm (passthru?)
}:

let
  self = stdenv.mkDerivation ({
    pname = "clang";
    inherit version;

    src = fetch "clang" "0ls2h3iv4finqyflyhry21qhc9cm9ga7g1zq21020p065qmm2y2p";

    unpackPhase = ''
      unpackFile $src
      mv clang-${version}* clang
      sourceRoot=$PWD/clang
      unpackFile ${clang-tools-extra_src}
      mv clang-tools-extra-* $sourceRoot/tools/extra
    '';

    nativeBuildInputs = [ cmake python3 ]
      ++ stdenv.lib.optional enableManpages python3.pkgs.sphinx
      ++ stdenv.lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;

    buildInputs = [ libxml2 llvm lld ];

    cmakeFlags = [
      "-DCMAKE_CXX_FLAGS=-std=c++11"
      "-DCLANGD_BUILD_XPC=OFF"
      "-DLLVM_ENABLE_RTTI=ON"
    ] ++ stdenv.lib.optionals enableManpages [
      "-DCLANG_INCLUDE_DOCS=ON"
      "-DLLVM_ENABLE_SPHINX=ON"
      "-DSPHINX_OUTPUT_MAN=ON"
      "-DSPHINX_OUTPUT_HTML=OFF"
      "-DSPHINX_WARNINGS_AS_ERRORS=OFF"
    ] ++ stdenv.lib.optionals enablePolly [
      "-DWITH_POLLY=ON"
      "-DLINK_POLLY_INTO_TOOLS=ON"
    ];

    patches = [
      ./purity.patch
      # https://reviews.llvm.org/D51899
      ./compiler-rt-baremetal.patch
      # make clang -xhip use $PATH to find executables
      ./HIP-use-PATH-9.patch
    ];

    postPatch = ''
      sed -i -e 's/DriverArgs.hasArg(options::OPT_nostdlibinc)/true/' \
             -e 's/Args.hasArg(options::OPT_nostdlibinc)/true/' \
             lib/Driver/ToolChains/*.cpp

      # Patch for standalone doc building
      sed -i '1s,^,find_package(Sphinx REQUIRED)\n,' docs/CMakeLists.txt
    '' + stdenv.lib.optionalString stdenv.hostPlatform.isMusl ''
      sed -i -e 's/lgcc_s/lgcc_eh/' lib/Driver/ToolChains/*.cpp
    '' + stdenv.lib.optionalString stdenv.hostPlatform.isDarwin ''
      substituteInPlace tools/extra/clangd/CMakeLists.txt \
        --replace "NOT HAVE_CXX_ATOMICS64_WITHOUT_LIB" FALSE
    '';

    outputs = [ "out" "lib" "python" ];

    # Clang expects to find LLVMgold in its own prefix
    postInstall = ''
      if [ -e ${llvm}/lib/LLVMgold.so ]; then
        ln -sv ${llvm}/lib/LLVMgold.so $out/lib
      fi

      ln -sv $out/bin/clang $out/bin/cpp

      # Move libclang to 'lib' output
      moveToOutput "lib/libclang.*" "$lib"
      moveToOutput "lib/libclang-cpp.*" "$lib"
      substituteInPlace $out/lib/cmake/clang/ClangTargets-release.cmake \
          --replace "\''${_IMPORT_PREFIX}/lib/libclang." "$lib/lib/libclang." \
          --replace "\''${_IMPORT_PREFIX}/lib/libclang-cpp." "$lib/lib/libclang-cpp."

      mkdir -p $python/bin $python/share/clang/
      mv $out/bin/{git-clang-format,scan-view} $python/bin
      if [ -e $out/bin/set-xcode-analyzer ]; then
        mv $out/bin/set-xcode-analyzer $python/bin
      fi
      mv $out/share/clang/*.py $python/share/clang
      rm $out/bin/c-index-test
    '';

    enableParallelBuilding = true;

    passthru = {
      isClang = true;
      inherit llvm;
    };

    meta = {
      description = "A c, c++, objective-c, and objective-c++ frontend for the llvm compiler";
      homepage    = "https://llvm.org/";
      license     = stdenv.lib.licenses.ncsa;
      platforms   = stdenv.lib.platforms.all;
    };
  } // stdenv.lib.optionalAttrs enableManpages {
    pname = "clang-manpages";

    buildPhase = ''
      make docs-clang-man
    '';

    installPhase = ''
      mkdir -p $out/share/man/man1
      # Manually install clang manpage
      cp docs/man/*.1 $out/share/man/man1/
    '';

    outputs = [ "out" ];

    doCheck = false;

    meta.description = "man page for Clang ${version}";
  });
in self
