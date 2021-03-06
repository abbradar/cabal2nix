{-# LANGUAGE CPP #-}

module Cabal2Nix.Generate ( cabal2nix, cabal2nix' ) where

import Cabal2Nix.Flags
import Cabal2Nix.License
import Cabal2Nix.Normalize
import Cabal2Nix.PostProcess
import Data.Maybe
import Distribution.Compiler
import Distribution.Nixpkgs.Haskell
import qualified Distribution.Package as Cabal
import qualified Distribution.PackageDescription as Cabal
import Distribution.PackageDescription.Configuration
import Distribution.System
import qualified Data.Set as Set

cabal2nix :: Cabal.FlagAssignment -> Cabal.GenericPackageDescription -> Derivation
cabal2nix flags' cabal = drv { cabalFlags = flags }
  where drv = cabal2nix' descr
        flags = normalizeCabalFlags (flags' ++ configureCabalFlags (Cabal.package (Cabal.packageDescription cabal)))
        Right (descr, _) = finalizePackageDescription
                            flags
                            (const True)
                            (Platform X86_64 Linux)                 -- shouldn't be hardcoded
#if MIN_VERSION_Cabal(1,22,0)
                            (unknownCompilerInfo (CompilerId GHC (Version [7,8,4] [])) NoAbiTag)
#else
                            (CompilerId GHC (Version [7,8,4] []))
#endif
                            []
                            cabal

cabal2nix' :: Cabal.PackageDescription -> Derivation
cabal2nix' tpkg = normalize $ postProcess $ normalize MkDerivation
  { pname          = let Cabal.PackageName x = Cabal.pkgName pkg in x
  , version        = Cabal.pkgVersion pkg
  , revision       = maybe 0 read (lookup "x-revision" xfields)
  , src            = error "cabal2nix left the src field undefined"
  , isLibrary      = isJust (Cabal.library tpkg)
  , isExecutable   = not (null (Cabal.executables tpkg))
  , extraFunctionArgs = Set.empty
  , buildDepends   = Set.fromList $ map unDep deps
  , testDepends    = Set.fromList $ map unDep tstDeps ++ concatMap Cabal.extraLibs tests
  , buildTools     = Set.fromList $ map unDep tools
  , extraLibs      = Set.fromList libs
  , pkgConfDeps    = Set.fromList pcs
  , configureFlags = Set.empty
  , cabalFlags     = configureCabalFlags pkg
  , runHaddock     = True
  , jailbreak      = False
  , doCheck        = True
  , testTarget     = ""
  , hyperlinkSource = True
  , enableSplitObjs = True
  , phaseOverrides = ""
  , editedCabalFile= if isJust (lookup "x-revision" xfields) then fromJust (lookup "x-cabal-file-hash" xfields) else ""
  , metaSection    = Meta
                   { homepage       = Cabal.homepage tpkg
                   , description    = Cabal.synopsis tpkg
                   , license        = fromCabalLicense (Cabal.license tpkg)
                   , platforms      = Set.empty
                   , hydraPlatforms = Set.empty
                   , maintainers    = Set.empty
                   , broken         = False
                   }
  }
  where
    xfields = Cabal.customFieldsPD tpkg
    pkg     = Cabal.package tpkg
    deps    = Cabal.buildDepends tpkg
    tests   = map Cabal.testBuildInfo (Cabal.testSuites tpkg)
    libDeps = map Cabal.libBuildInfo (maybeToList (Cabal.library tpkg))
    exeDeps = map Cabal.buildInfo (Cabal.executables tpkg)
    tstDeps = concatMap Cabal.buildTools tests ++ concatMap Cabal.pkgconfigDepends tests ++
              concatMap Cabal.targetBuildDepends tests
    tools   = concatMap Cabal.buildTools (libDeps ++ exeDeps)
    libs    = concatMap Cabal.extraLibs (libDeps ++ exeDeps)
    pcs     = map unDep (concatMap Cabal.pkgconfigDepends (libDeps ++ exeDeps))

unDep :: Cabal.Dependency -> String
unDep (Cabal.Dependency (Cabal.PackageName x) _) = x
