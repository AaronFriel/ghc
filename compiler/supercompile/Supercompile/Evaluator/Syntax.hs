module Supercompile.Evaluator.Syntax where

import Supercompile.Core.FreeVars
import Supercompile.Core.Renaming
import Supercompile.Core.Size
import Supercompile.Core.Syntax
import Supercompile.Core.Tag

import Supercompile.Utilities

import qualified Data.Map as M


type Anned = O Tagged (O Sized FVed)
type AnnedTerm = Anned (TermF Anned)
type AnnedValue = ValueF Anned
type AnnedAlt = AltF Anned

annee :: Anned a -> a
annee = extract

annedSize :: Anned a -> Size
annedSize = size . unComp . tagee . unComp

annedFreeVars :: Anned a -> FreeVars
annedFreeVars = freeVars . sizee . unComp . tagee . unComp

annedTag :: Anned a -> Tag
annedTag = tag . unComp


annedVarFreeVars' = taggedSizedFVedVarFreeVars'
annedTermFreeVars = taggedSizedFVedTermFreeVars
annedTermFreeVars' = taggedSizedFVedTermFreeVars'
annedValueFreeVars = taggedSizedFVedValueFreeVars
annedValueFreeVars' = taggedSizedFVedValueFreeVars'
annedAltsFreeVars = taggedSizedFVedAltsFreeVars

annedVarSize' = taggedSizedFVedVarSize'
annedTermSize' = taggedSizedFVedTermSize'
annedTermSize = taggedSizedFVedTermSize
annedValueSize' = taggedSizedFVedValueSize'
annedValueSize = taggedSizedFVedValueSize
annedAltsSize = taggedSizedFVedAltsSize

renameAnnedTerm = renameTaggedSizedFVedTerm :: InScopeSet -> Renaming -> AnnedTerm -> AnnedTerm
renameAnnedValue = renameTaggedSizedFVedValue
renameAnnedValue' = renameTaggedSizedFVedValue'
renameAnnedAlts = renameTaggedSizedFVedAlts

detagAnnedTerm = taggedSizedFVedTermToFVedTerm
detagAnnedValue = taggedSizedFVedValueToFVedValue
detagAnnedValue' = taggedSizedFVedValue'ToFVedValue'
detagAnnedAlts = taggedSizedFVedAltsToFVedAlts


annedVar :: Tag -> Var -> Anned Var
annedVar   tg x = Comp (Tagged tg (Comp (Sized (annedVarSize' x)   (FVed (annedVarFreeVars' x)  x))))

annedTerm :: Tag -> TermF Anned -> AnnedTerm
annedTerm  tg e = Comp (Tagged tg (Comp (Sized (annedTermSize' e)  (FVed (annedTermFreeVars' e)  e))))

annedValue :: Tag -> ValueF Anned -> Anned AnnedValue
annedValue tg v = Comp (Tagged tg (Comp (Sized (annedValueSize' v) (FVed (annedValueFreeVars' v) v))))


toAnnedTerm :: UniqSupply -> Term -> AnnedTerm
toAnnedTerm tag_ids = tagFVedTerm tag_ids . reflect


data QA = Question Var
        | Answer   (ValueF Anned)

instance Outputable QA where
    pprPrec prec = pPrintPrec prec . qaToAnnedTerm'

qaToAnnedTerm' :: QA -> TermF Anned
qaToAnnedTerm' (Question x) = Var x
qaToAnnedTerm' (Answer v)   = Value v


type UnnormalisedState = (Heap, Stack, In AnnedTerm)
type State = (Heap, Stack, In (Anned QA))

denormalise :: State -> UnnormalisedState
denormalise (h, k, (rn, qa)) = (h, k, (rn, fmap qaToAnnedTerm' qa))


-- Invariant: LetBound things cannot refer to LambdaBound things.
--
-- This is motivated by:
--  1. There is no point lambda-abstracting over things referred to by LetBounds because the resulting h-function would be
--     trapped under the appropriate let-binding anyway, at which point all the lambda-abstracted things would be in scope as FVs.
--  2. It allows (but does not require) the matcher to look into the RHS of LetBound stuff (rather than just doing nominal
--     matching).
data HowBound = InternallyBound | LambdaBound | LetBound
              deriving (Eq, Show)

instance Outputable HowBound where
    ppr = text . show

data HeapBinding = HB { howBound :: HowBound, heapBindingMeaning :: Either (Maybe Tag) (In AnnedTerm) }

pPrintPrecAnned :: (Outputable1 f, Outputable a)
                => (f a -> FreeVars)
                -> (InScopeSet -> Renaming -> f a -> f a)
                -> Rational -> In (f a) -> SDoc
pPrintPrecAnned fvs rename prec in_e = pprPrec prec $ Wrapper1 $ renameIn (rename (mkInScopeSet (inFreeVars fvs in_e))) in_e

pPrintPrecAnnedAlts :: In [AnnedAlt] -> [(AltCon, PrettyFunction)]
pPrintPrecAnnedAlts in_alts = map (second (\e -> PrettyFunction $ \prec -> pprPrec prec (Wrapper1 e))) $ renameIn (renameAnnedAlts (mkInScopeSet (inFreeVars annedAltsFreeVars in_alts))) in_alts

pPrintPrecAnnedValue :: Rational -> In (Anned AnnedValue) -> SDoc
pPrintPrecAnnedValue prec in_e = pPrintPrecValue prec $ extract $ renameIn (renameAnnedValue (mkInScopeSet (inFreeVars annedValueFreeVars in_e))) in_e

pPrintPrecAnnedTerm :: Rational -> In AnnedTerm -> SDoc
pPrintPrecAnnedTerm prec in_e = pprPrec prec $ Wrapper1 $ renameIn (renameAnnedTerm (mkInScopeSet (inFreeVars annedTermFreeVars in_e))) in_e

instance Outputable HeapBinding where
    pprPrec prec (HB how mb_in_e) = case how of
        InternallyBound -> either (const empty) (pPrintPrecAnnedTerm prec) mb_in_e
        LambdaBound     -> text "λ" <> angles (either (const empty) (pPrintPrecAnnedTerm noPrec) mb_in_e)
        LetBound        -> text "l" <> angles (either (const empty) (pPrintPrecAnnedTerm noPrec) mb_in_e)

lambdaBound :: HeapBinding
lambdaBound = HB LambdaBound (Left Nothing)

internallyBound :: In AnnedTerm -> HeapBinding
internallyBound in_e = HB InternallyBound (Right in_e)

environmentallyBound :: Tag -> HeapBinding
environmentallyBound tg = HB LetBound (Left (Just tg))

type PureHeap = M.Map (Out Var) HeapBinding
data Heap = Heap PureHeap InScopeSet

instance Outputable Heap where
    pprPrec prec (Heap h _) = pprPrec prec h


type Stack = [Tagged StackFrame]
data StackFrame = Apply (Out Var)
                | Scrutinise (Out Var) (Out Type) (In [AnnedAlt])
                | PrimApply PrimOp [In (Anned AnnedValue)] [In AnnedTerm]
                | Update (Out Var)

instance Outputable StackFrame where
    pprPrec prec kf = case kf of
        Apply x'                  -> pPrintPrecApp prec (PrettyDoc $ text "[_]") x'
        Scrutinise x' _ty in_alts -> pPrintPrecCase prec (PrettyDoc $ text "[_]") x' (pPrintPrecAnnedAlts in_alts)
        PrimApply pop in_vs in_es -> pPrintPrecPrimOp prec pop (map (PrettyFunction . flip pPrintPrecAnnedValue) in_vs ++ map (PrettyFunction . flip pPrintPrecAnnedTerm) in_es)
        Update x'                 -> pPrintPrecApp prec (PrettyDoc $ text "update") x'


heapBindingTerm :: HeapBinding -> Maybe (In AnnedTerm)
heapBindingTerm = either (const Nothing) Just . heapBindingMeaning

heapBindingTag :: HeapBinding -> Maybe Tag
heapBindingTag = either id (Just . annedTag . snd) . heapBindingMeaning

-- | Size of HeapBinding for Deeds purposes
heapBindingSize :: HeapBinding -> Size
heapBindingSize (HB InternallyBound (Right (_, e))) = annedSize e
heapBindingSize _                                   = 0

-- | Size of StackFrame for Deeds purposes
stackFrameSize :: StackFrame -> Size
stackFrameSize kf = 1 + case kf of
    Apply _                  -> 0
    Scrutinise _ _ (_, alts) -> annedAltsSize alts
    PrimApply _ in_vs in_es  -> sum (map (annedValueSize . snd) in_vs ++ map (annedTermSize . snd) in_es)
    Update _                 -> 0

stateSize :: State -> Size
stateSize (h, k, in_qa) = heapSize h + stackSize k + qaSize (snd in_qa)
          where qaSize = annedSize . fmap qaToAnnedTerm'
                heapSize (Heap h _) = sum (map heapBindingSize (M.elems h))
                stackSize = sum . map (stackFrameSize . tagee)
