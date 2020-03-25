module PubGrub.GrubState

import PubGrub.Types.Assignment
import PubGrub.Types.Incomp
import PubGrub.Types.PackageTracking
import PubGrub.Types.PartialSolution
import PubGrub.Types.Term
import PubGrub.SemverUtils
import Core.ManifestTypes
import Semver.Range
import Semver.Version
import Control.Monad.State
import Data.AVL.Dict

%access public export

--------------------------------------------------------------------------------
-- The State of Version Solving
--------------------------------------------------------------------------------

||| The type used to keep track of the state of PubGrub version solving.
|||
||| - PartialSolution keeps tract of the current assignments.
||| - IncompMap stores the current incompatibilties/
||| - Integer stores the current decision level (starts at 0, and increases by
|||   1 with each decision that is added to the partial solution).
||| - PkgVersions stores the available versions of packages which have been
|||   retrieved from their source so far (packages are loaded as they are
|||   referenced as dependancies).
||| - Manifests stores the parsed manifest file for each package version once it
|||   has been parsed, so it doesn't need to be reparsed each time it is
|||   referenced.
||| - PkgName stores the name of the root package
data GrubState = MkGrubState PartialSolution IncompMap Integer PkgVersions Manifests PkgName

%name GrubState state


--------------------------------------------------------------------------------
-- Getters for GrubState
--------------------------------------------------------------------------------

getPartialSolution : GrubState -> PartialSolution
getPartialSolution (MkGrubState ps _ _ _ _ _) = ps

getIncompMap : GrubState -> IncompMap
getIncompMap (MkGrubState _ iMap _ _ _ _) = iMap

getDecisionLevel : GrubState -> Integer
getDecisionLevel (MkGrubState _ _ decLevel _ _ _) = decLevel

getPkgVersions : GrubState -> PkgVersions
getPkgVersions (MkGrubState _ _ _ pVersions _ _) = pVersions

getManifests : GrubState -> Manifests
getManifests (MkGrubState _ _ _ _ mans _) = mans

getRootPkg : GrubState -> PkgName
getRootPkg (MkGrubState _ _ _ _ _ root) = root


--------------------------------------------------------------------------------
-- Stateful setters for GrubState
--------------------------------------------------------------------------------

setPartialSolution : PartialSolution -> StateT GrubState IO ()
setPartialSolution ps =
  do  (MkGrubState _ iMap decLevel pVersions mans root) <- get
      put (MkGrubState ps iMap decLevel pVersions mans root)

setIncompMap : IncompMap -> StateT GrubState IO ()
setIncompMap iMap =
  do  (MkGrubState ps _ decLevel pVersions mans root) <- get
      put (MkGrubState ps iMap decLevel pVersions mans root)

setDecisionLevel : Integer -> StateT GrubState IO ()
setDecisionLevel decLevel =
  do  (MkGrubState ps iMap _ pVersions mans root) <- get
      put (MkGrubState ps iMap decLevel pVersions mans root)

setPkgVersions : PkgVersions -> StateT GrubState IO ()
setPkgVersions pVersions =
  do  (MkGrubState ps iMap decLevel _ mans root) <- get
      put (MkGrubState ps iMap decLevel pVersions mans root)

setManifests : Manifests -> StateT GrubState IO ()
setManifests mans =
  do  (MkGrubState ps iMap decLevel pVersions _ root) <- get
      put (MkGrubState ps iMap decLevel pVersions mans root)


--------------------------------------------------------------------------------
-- Special getters for GrubState
--------------------------------------------------------------------------------

getI : PkgName -> GrubState -> List Incomp
getI n (MkGrubState _ is _ _ _ _) = getI' n is

addI : Incomp -> StateT GrubState IO ()
addI i = do  (MkGrubState x is y z w q) <- get
             put (MkGrubState x (addI' i is) y z w q)

getPSForPkg : PkgName -> GrubState -> List Assignment
getPSForPkg n (MkGrubState ps _ _ _ _ _) = getPSForPkg' n ps

||| Extract a list of all decisions from the partial solution
extractDecs : GrubState -> List (PkgName, Version)
extractDecs (MkGrubState ps _ _ _ _ _) = extractDecs' (snd ps)
  where
    extractDecs' : List (PkgName, Assignment) -> List (PkgName, Version)
    extractDecs' [] = []
    extractDecs' ((n, (Derivation v _ _)) :: as) =
      extractDecs' as
    extractDecs' ((n, (Decision v _)) :: as)     =
      (n, v) :: (extractDecs' as)

||| Find the list of versions which are allowed by the partial solution for a
||| given package, for the given grub state.
vsInPS : GrubState -> PkgName -> List Version
vsInPS (MkGrubState ps _ _ pvs mans _) n =
  do  let Just vs
          = lookup n pvs
          | Nothing  => []
      vsInPS' n vs ps

||| Get a list of all packages which do not yet have a decision in the partial
||| solution.
psNoDec : GrubState -> List PkgName
psNoDec (MkGrubState ps _ _ _ _ _) = map fst $ filter (pkgHasNoDec . snd) $ toList $ fst ps


--------------------------------------------------------------------------------
-- Special setters for GrubState
--------------------------------------------------------------------------------

addToPS : PkgName -> Assignment -> StateT GrubState IO ()
addToPS n a =
  do  (MkGrubState ps x y z w q) <- get
      put (MkGrubState (addToPS' n a ps) x y z w q)

||| Add a manifest to the dictionary of manifests, indexed by package name and
||| value.
addManifest : Manifest -> StateT GrubState IO ()
addManifest (MkManifest n v xs m) =
  do  (MkGrubState w x y z mans q) <- get
      put (MkGrubState w x y z (insert (n, v) (MkManifest n v xs m) mans) q)

||| Add a list of available versions for a given package to the dictionary of
||| package versions.
addVersionList : PkgName -> List Version -> StateT GrubState IO ()
addVersionList n vs =
  do  (MkGrubState w x y pVersions z q) <- get
      put (MkGrubState w x y (insert n vs pVersions) z q)


||| Add a set of ranges as individual positive incompatibilities
addRangesAsIncomps : PkgName -> List Range -> StateT GrubState IO ()
addRangesAsIncomps n [] = pure ()
addRangesAsIncomps n (x :: xs) = addI [ (n, (Pos x)) ]

||| Add a list of incompatibilties to the partial solution
addIs : List Incomp -> StateT GrubState IO ()
addIs [] = pure ()
addIs (x :: xs) = do  addI x
                      addIs xs


--------------------------------------------------------------------------------
-- Utils
--------------------------------------------------------------------------------

||| Find the package which has the smallest number of versions allowed by the
||| partial solution. This is a decent heuristic for improving solve time, as
||| conflicts are more likely to be found quickly for packages with fewer
||| versions to choose from.
minVsInPS : GrubState -> PkgName
minVsInPS state =
  do  let (k :: ks) = psNoDec state
      minVsInPS' state ks k (length (vsInPS state k))
  where
    minVsInPS' :  GrubState
               -> List PkgName
               -> (minName : PkgName)
               -> (minVal : Nat)
               -> PkgName
    minVsInPS' state [] minName minVal = minName
    minVsInPS' state (n :: ns) minName minVal =
      do  let val = length $ vsInPS state n
          if
            (val < minVal)
          then
            minVsInPS' state ns n val
          else
            minVsInPS' state ns minName minVal