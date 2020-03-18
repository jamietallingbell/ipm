module PubGrub.Algorithm

-- TODO remove redundant ones
import PubGrub.Types
import Semver.Range
import Semver.Version
import Core.ManifestTypes
import Core.IpmError
import Util.SemverExtras
import Data.AVL.Dict

{-
Check if a term is satisfied by the PS.

If a decision is come across, stop looping and use that (decisions should be
the first found if they exist.)

The list of assignments here only apply to this PkgName.
-}

termCheck : PkgName -> Term -> List Assignment -> TermResult
termCheck n t [] =
    ?termCheck_rhs_1
termCheck n t ((Decision v _) :: as) = case

-- incompCheck :

unitPropLoop : GrubState -> (changed : List PkgName) -> List Incomp -> Either IpmError (GrubState, List PkgName)
unitPropLoop state changed [] = Right (state, changed)
unitPropLoop state changed (i :: is) = ?unitPropLoop_rhs_2

unitProp : GrubState -> (changed : List PkgName) -> Either IpmError GrubState
unitProp state [] = Right state
unitProp state (package :: changed) =
    do  let Right (newState, newChanged)
                    = unitPropLoop state changed (getI package state)
                    | Left err => Left err
        unitProp newState newChanged

decMake : GrubState -> Either (List (PkgName, Version)) (GrubState, PkgName)

mainLoop : GrubState -> PkgName -> Either IpmError (List (PkgName, Version))
mainLoop state next =
    do  let Right newState
                    = unitProp state [ next ]
                    | Left err => Left err
        let Right (newNewState, newNext)
                    = decMake newState
                    | Left solution => Right solution
        mainLoop newNewState newNext