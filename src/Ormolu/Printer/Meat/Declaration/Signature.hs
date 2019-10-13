{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- | Type signature declarations.
module Ormolu.Printer.Meat.Declaration.Signature
  ( p_sigDecl,
    p_typeAscription,
    p_activation,
  )
where

import BasicTypes
import BooleanFormula
import Control.Monad
import Data.Bool (bool)
import GHC
import Ormolu.Printer.Combinators
import Ormolu.Printer.Meat.Common
import Ormolu.Printer.Meat.Type
import Ormolu.Utils

p_sigDecl ∷ Sig GhcPs → R ()
p_sigDecl = \case
  TypeSig NoExt names hswc → p_typeSig True names hswc
  PatSynSig NoExt names hsib → p_patSynSig names hsib
  ClassOpSig NoExt def names hsib → p_classOpSig def names hsib
  FixSig NoExt sig → p_fixSig sig
  InlineSig NoExt name inlinePragma → p_inlineSig name inlinePragma
  SpecSig NoExt name ts inlinePragma → p_specSig name ts inlinePragma
  SpecInstSig NoExt _ hsib → p_specInstSig hsib
  MinimalSig NoExt _ booleanFormula → p_minimalSig booleanFormula
  CompleteMatchSig NoExt _sourceText cs ty → p_completeSig cs ty
  SCCFunSig NoExt _ name literal → p_sccSig name literal
  _ → notImplemented "certain types of signature declarations"

p_typeSig ∷
  -- | Should the tail of the names be indented
  Bool →
  -- | Names (before @::@)
  [Located RdrName] →
  -- | Type
  LHsSigWcType GhcPs →
  R ()
p_typeSig _ [] _ = return () -- should not happen though
p_typeSig indentTail (n : ns) hswc = do
  p_rdrName n
  if null ns
    then p_typeAscription hswc
    else bool id inci indentTail $ do
      comma
      breakpoint
      sep (comma >> breakpoint) p_rdrName ns
      p_typeAscription hswc

p_typeAscription ∷
  LHsSigWcType GhcPs →
  R ()
p_typeAscription HsWC {..} = do
  space
  inci $ do
    txt "∷"
    let t = hsib_body hswc_body
    if hasDocStrings (unLoc t)
      then newline
      else breakpoint
    located t p_hsType
p_typeAscription (XHsWildCardBndrs NoExt) = notImplemented "XHsWildCardBndrs"

p_patSynSig ∷
  [Located RdrName] →
  HsImplicitBndrs GhcPs (LHsType GhcPs) →
  R ()
p_patSynSig names hsib = do
  txt "pattern"
  let body = p_typeSig False names HsWC {hswc_ext = NoExt, hswc_body = hsib}
  if length names > 1
    then breakpoint >> inci body
    else space >> body

p_classOpSig ∷
  -- | Whether this is a \"default\" signature
  Bool →
  -- | Names (before @::@)
  [Located RdrName] →
  -- | Type
  HsImplicitBndrs GhcPs (LHsType GhcPs) →
  R ()
p_classOpSig def names hsib = do
  when def (txt "default" >> space)
  p_typeSig True names HsWC {hswc_ext = NoExt, hswc_body = hsib}

p_fixSig ∷
  FixitySig GhcPs →
  R ()
p_fixSig = \case
  FixitySig NoExt names (Fixity _ n dir) → do
    txt $ case dir of
      InfixL → "infixl"
      InfixR → "infixr"
      InfixN → "infix"
    space
    atom n
    space
    sitcc $ sep (comma >> breakpoint) p_rdrName names
  XFixitySig NoExt → notImplemented "XFixitySig"

p_inlineSig ∷
  -- | Name
  Located RdrName →
  -- | Inline pragma specification
  InlinePragma →
  R ()
p_inlineSig name InlinePragma {..} = pragmaBraces $ do
  p_inlineSpec inl_inline
  space
  case inl_rule of
    ConLike → txt "CONLIKE"
    FunLike → return ()
  space
  p_activation inl_act
  space
  p_rdrName name

p_specSig ∷
  -- | Name
  Located RdrName →
  -- | The types to specialize to
  [LHsSigType GhcPs] →
  -- | For specialize inline
  InlinePragma →
  R ()
p_specSig name ts InlinePragma {..} = pragmaBraces $ do
  txt "SPECIALIZE"
  space
  p_inlineSpec inl_inline
  space
  p_activation inl_act
  space
  p_rdrName name
  space
  txt "∷"
  breakpoint
  inci $ sep (comma >> breakpoint) (located' p_hsType . hsib_body) ts

p_inlineSpec ∷ InlineSpec → R ()
p_inlineSpec = \case
  Inline → txt "INLINE"
  Inlinable → txt "INLINEABLE"
  NoInline → txt "NOINLINE"
  NoUserInline → return ()

p_activation ∷ Activation → R ()
p_activation = \case
  NeverActive → return ()
  AlwaysActive → return ()
  ActiveBefore _ n → do
    txt "[~"
    atom n
    txt "]"
  ActiveAfter _ n → do
    txt "["
    atom n
    txt "]"

p_specInstSig ∷ LHsSigType GhcPs → R ()
p_specInstSig hsib =
  pragma "SPECIALIZE instance" . inci $
    located (hsib_body hsib) p_hsType

p_minimalSig ∷
  -- | Boolean formula
  LBooleanFormula (Located RdrName) →
  R ()
p_minimalSig =
  located' $ \booleanFormula →
    pragma "MINIMAL" (inci $ p_booleanFormula booleanFormula)

p_booleanFormula ∷
  -- | Boolean formula
  BooleanFormula (Located RdrName) →
  R ()
p_booleanFormula = \case
  Var name → p_rdrName name
  And xs →
    sitcc $
      sep
        (comma >> breakpoint)
        (located' p_booleanFormula)
        xs
  Or xs →
    sitcc $
      sep
        (breakpoint >> txt "| ")
        (located' p_booleanFormula)
        xs
  Parens l → located l (parens N . p_booleanFormula)

p_completeSig ∷
  -- | Constructors\/patterns
  Located [Located RdrName] →
  -- | Type
  Maybe (Located RdrName) →
  R ()
p_completeSig cs' mty =
  located cs' $ \cs →
    pragma "COMPLETE" . inci $ do
      sitcc $ sep (comma >> breakpoint) p_rdrName cs
      forM_ mty $ \ty → do
        space
        txt "∷"
        breakpoint
        inci (p_rdrName ty)

p_sccSig ∷ Located (IdP GhcPs) → Maybe (Located StringLiteral) → R ()
p_sccSig loc literal = pragma "SCC" . inci $ do
  p_rdrName loc
  forM_ literal $ \x → do
    breakpoint
    atom x
