{
  description = "Souper superoptimizer with LLVM 19";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # KLEE source (using the branch compatible with Souper)
    klee-src = {
      url = "github:regehr/klee/klee-for-souper-17-2";
      flake = false;
    };

    # Alive2 source
    alive2-src = {
      url = "github:manasij7479/alive2/v7";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, klee-src, alive2-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        llvm = pkgs.llvmPackages_19;
        
        # Alive2 derivation
        alive2 = pkgs.stdenv.mkDerivation {
          pname = "alive2";
          version = "v7";
          src = alive2-src;

          nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.python3 pkgs.git pkgs.re2c ];
          buildInputs = [ 
            llvm.llvm 
            pkgs.z3 
            pkgs.hiredis
          ];

          cmakeFlags = [
            "-DBUILD_TV=ON"
            "-DZ3_INCLUDE_DIR=${pkgs.z3.dev}/include"
            "-DZ3_LIBRARIES=${pkgs.z3.lib}/lib/libz3.so"
            "-DCMAKE_CXX_FLAGS=-fexceptions" 
          ];

          # Alive2 insists on LLVM having EH/RTTI enabled, but standard Nix LLVM might not have it.
          # We patch out the check.
          # Alive2 insists on LLVM having EH/RTTI enabled, but standard Nix LLVM might not have it.
          # We patch out the check.
          # Also init a dummy git repo so 'git describe' works
          postPatch = ''
            sed -i '/LLVM must be built with/d' CMakeLists.txt
            
            git init
            git config user.email "you@example.com"
            git config user.name "Your Name"
            git commit --allow-empty -m "dummy"
            git tag v7
            
            sed -i '/project/a add_compile_options(-fexceptions)' CMakeLists.txt
            
            sed -i 's/llvm::llvm_shutdown_obj/ \/\/ llvm::llvm_shutdown_obj/g' tools/*.cpp
            sed -i 's/llvm_shutdown_obj/ \/\/ llvm_shutdown_obj/g' tools/*.cpp
          '';
          
          postInstall = ''
             mkdir -p $out/lib
             find . -name "*.a" -exec cp {} $out/lib \;
             mkdir -p $out/include
             for dir in ir util smt llvm_util cache tools; do
               cp -r ${alive2-src}/$dir $out/include/
             done
             # Copy generated header if it exists in build dir
             if [ -f version_gen.h ]; then
                cp version_gen.h $out/include/
             fi
             # Create symlink for Souper which uses #include "alive2/..."
             ln -s . $out/include/alive2
          '';
        };

      in
      {
        packages.alive2 = alive2;

        packages.souper = pkgs.stdenv.mkDerivation {
          pname = "souper";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.python3 pkgs.git ];
          buildInputs = [ 
            llvm.llvm 
            pkgs.z3 
            pkgs.hiredis
            alive2
            pkgs.zstd
            pkgs.ncurses
            pkgs.libxml2
          ];

          # Pass locations of dependencies to CMake
          cmakeFlags = [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DKLEE_SRC_DIR=${klee-src}"
            "-DALIVE_DIR=${alive2}"
            "-DLLVM_DIR=${llvm.llvm.dev}/lib/cmake/llvm"
            "-DZ3_INCLUDE_DIR=${pkgs.z3.dev}/include"
            "-DZ3_LIBRARIES=${pkgs.z3.lib}/lib/libz3.so"
            "-DHIREDIS_INCLUDE_DIR=${pkgs.hiredis}/include/hiredis"
            "-DHIREDIS_LIBRARIES=${pkgs.hiredis}/lib/libhiredis.so"
            "-DZSTD_LIBRARY_DIR=${pkgs.zstd.out}/lib"
            "-DZ3=${pkgs.z3}/bin/z3"
          ];
          
          # We might need to help it find z3 or hiredis if standard paths fail
          installPhase = ''
            mkdir -p $out/bin $out/lib
            cp souper souper-check souper-interpret souper2llvm count-insts $out/bin/
            cp libsouperPass.so $out/lib/
          '';
          # but they are in buildInputs so usually it works.
        };

        packages.default = self.packages.${system}.souper;

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.cmake
            pkgs.ninja
            llvm.llvm
            pkgs.z3
            pkgs.hiredis
            pkgs.python3
            pkgs.gdb
          ];

          # Environment variables for the shell
          shellHook = ''
            export KLEE_SRC_DIR=${klee-src}
            export ALIVE_DIR=${alive2}
            export LLVM_DIR=${llvm.llvm.dev}/lib/cmake/llvm
            echo "Environment setup for Souper with LLVM 19"
          '';
        };
      }
    );
}
