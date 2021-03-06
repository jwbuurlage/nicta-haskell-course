{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE OverloadedStrings #-}

module Course.StateT where

import Course.Applicative
import Course.Core
import Course.Functor
import Course.Id
import Course.List
import Course.Monad
import Course.Optional
import Course.State
import qualified Data.Set as S
import qualified Prelude as P

-- $setup
-- >>> import Test.QuickCheck
-- >>> import qualified Prelude as P(fmap)
-- >>> instance Arbitrary a => Arbitrary (List a) where arbitrary = P.fmap listh arbitrary
-- | A `StateT` is a function from a state value `s` to a functor f of (a produced value `a`, and a resulting state `s`).
newtype StateT s f a = StateT
  { runStateT :: s -> f (a, s)
  }

-- | Implement the `Functor` instance for @StateT s f@ given a @Functor f@.
--
-- >>> runStateT ((+1) <$> (pure 2) :: StateT Int List Int) 0
-- [(3,0)]
instance Functor f =>
         Functor (StateT s f) where
  (<$>) :: (a -> b) -> StateT s f a -> StateT s f b
  g <$> (StateT runx) = StateT (\s -> first g <$> runx s)

-- | Implement the `Applicative` instance for @StateT s f@ given a @Monad f@.
--
-- >>> runStateT (pure 2) 0
-- (2,0)
--
-- >>> runStateT ((pure 2) :: StateT Int List Int) 0
-- [(2,0)]
--
-- >>> runStateT (pure (+2) <*> ((pure 2) :: StateT Int List Int)) 0
-- [(4,0)]
--
-- >>> import qualified Prelude as P
-- >>> runStateT (StateT (\s -> Full ((+2), s P.++ [1])) <*> (StateT (\s -> Full (2, s P.++ [2])))) [0]
-- Full (4,[0,1,2])
--
-- >>> runStateT (StateT (\s -> ((+2), s P.++ [1]) :. ((+3), s P.++ [1]) :. Nil) <*> (StateT (\s -> (2, s P.++ [2]) :. Nil))) [0]
-- [(4,[0,1,2]),(5,[0,1,2])]
instance Monad f =>
         Applicative (StateT s f) where
  pure :: a -> StateT s f a
  pure x = StateT (\s -> pure (x, s))
  (<*>) :: StateT s f (a -> b) -> StateT s f a -> StateT s f b
  (StateT runf) <*> (StateT runx) = StateT (\s -> alpha runx (runf s))
    where
      alpha :: (s -> f (a, s)) -> f (a -> b, s) -> f (b, s)
      alpha r y = (beta r) =<< y
      beta :: (s -> f (a, s)) -> (a -> b, s) -> f (b, s)
      beta r' (f, s') = first f <$> (r' s')
  -- (runf s) :: f (a -> b, s')
  -- (runx s') :: f (a, s'')

-- | Implement the `Monad` instance for @StateT s f@ given a @Monad f@.
-- Make sure the state value is passed through in `bind`.
--
-- >>> runStateT ((const $ putT 2) =<< putT 1) 0
-- ((),2)
--
-- >>> let modify f = StateT (\s -> pure ((), f s)) in runStateT (modify (+1) >>= \() -> modify (*2)) 7
-- ((),16)
instance Monad f =>
         Monad (StateT s f) where
  (=<<) :: (a -> StateT s f b) -> StateT s f a -> StateT s f b
  f =<< (StateT r) =
    StateT (\e -> join (carryApply <$> ((first (runStateT . f)) <$> (r e))))
    where
      carryApply :: (a -> b, a) -> b
      carryApply (f', x) = f' x

-- | A `State'` is `StateT` specialised to the `Id` functor.
type State' s a = StateT s Id a

-- | Provide a constructor for `State'` values
--
-- >>> runStateT (state' $ runState $ put 1) 0
-- Id ((),1)
state' :: (s -> (a, s)) -> State' s a
state' f = StateT (pure . f)

-- | Provide an unwrapper for `State'` values.
--
-- >>> runState' (state' $ runState $ put 1) 0
-- ((),1)
runState' :: State' s a -> s -> (a, s)
runState' (StateT k) = runId . k

-- | Run the `StateT` seeded with `s` and retrieve the resulting state.
execT
  :: Functor f
  => StateT s f a -> s -> f s
execT r s = snd <$> runStateT r s

-- | Run the `State` seeded with `s` and retrieve the resulting state.
exec' :: State' s a -> s -> s
exec' r s = snd $ runState' r s

-- | Run the `StateT` seeded with `s` and retrieve the resulting value.
evalT
  :: Functor f
  => StateT s f a -> s -> f a
evalT r s = fst <$> runStateT r s

-- | Run the `State` seeded with `s` and retrieve the resulting value.
eval' :: State' s a -> s -> a
eval' r s = fst $ runState' r s

-- | A `StateT` where the state also distributes into the produced value.
--
-- >>> (runStateT (getT :: StateT Int List Int) 3)
-- [(3,3)]
getT
  :: Monad f
  => StateT s f s
getT = StateT (\s -> pure (s, s))

-- | A `StateT` where the resulting state is seeded with the given value.
--
-- >>> runStateT (putT 2) 0
-- ((),2)
--
-- >>> runStateT (putT 2 :: StateT Int List ()) 0
-- [((),2)]
putT
  :: Monad f
  => s -> StateT s f ()
putT s = StateT (\_ -> pure ((), s))

-- | Remove all duplicate elements in a `List`.
--
-- /Tip:/ Use `filtering` and `State'` with a @Data.Set#Set@.
--
-- prop> distinct' xs == distinct' (flatMap (\x -> x :. x :. Nil) xs)
distinct'
  :: (Ord a, Num a)
  => List a -> List a
distinct' xs =  fst $ (runState' (filtering (\x -> state' (\s -> (S.notMember x s, S.insert x s))) xs)) S.empty


-- | Remove all duplicate elements in a `List`.
-- However, if you see a value greater than `100` in the list,
-- abort the computation by producing `Empty`.
--
-- /Tip:/ Use `filtering` and `StateT` over `Optional` with a @Data.Set#Set@.
--
-- >>> distinctF $ listh [1,2,3,2,1]
-- Full [1,2,3]
--
-- >>> distinctF $ listh [1,2,3,2,1,101]
-- Empty
distinctF
  :: (Ord a, Num a)
  => List a -> Optional (List a)
distinctF xs = fst <$> runStateT
        (filtering (\x ->
            StateT (\s ->
                if x <= 100 then Full (S.notMember x s, S.insert x s) else Empty)) xs)
                S.empty

-- note f = (StateT Set Optional) is instance of applicative

-- filtering has signature List a -> f List a
-- f is StateT
-- List a -> (StateT Optional) (List a)

-- | An `OptionalT` is a functor of an `Optional` value.
data OptionalT f a = OptionalT
  { runOptionalT :: f (Optional a)
  }

-- | Implement the `Functor` instance for `OptionalT f` given a Functor f.
--
-- >>> runOptionalT $ (+1) <$> OptionalT (Full 1 :. Empty :. Nil)
-- [Full 2,Empty]
instance Functor f =>
         Functor (OptionalT f) where
  (<$>) :: (a -> b) -> OptionalT f a -> OptionalT f b
  g <$> OptionalT x = OptionalT $ (<$>) g <$> x

-- | Implement the `Applicative` instance for `OptionalT f` given a Applicative f.
--
-- >>> runOptionalT $ OptionalT (Full (+1) :. Full (+2) :. Nil) <*> OptionalT (Full 1 :. Empty :. Nil)
-- [Full 2,Empty,Full 3,Empty]
instance Applicative f =>
         Applicative (OptionalT f) where
  pure :: a -> OptionalT f a
  pure x = OptionalT (pure (Full x))

  (<*>) :: OptionalT f (a -> b) -> OptionalT f a -> OptionalT f b
  OptionalT g <*> OptionalT x = OptionalT ((<$>) (<*>) g <*> x)
--                                           ^-- f ^-- M  ^-- f

-- | Implement the `Monad` instance for `OptionalT f` given a Monad f.
--
-- >>> runOptionalT $ (\a -> OptionalT (Full (a+1) :. Full (a+2) :. Nil)) =<< OptionalT (Full 1 :. Empty :. Nil)
-- [Full 2,Full 3,Empty]
instance Monad f =>
         Monad (OptionalT f) where
  (=<<) :: (a -> OptionalT f b) -> OptionalT f a -> OptionalT f b
  g =<< (OptionalT x) = OptionalT $ (\o -> case o of
    Empty -> pure Empty
    Full y -> runOptionalT (g y)) =<< x

-- | A `Logger` is a pair of a list of log values (`[l]`) and an arbitrary value (`a`).
data Logger l a =
  Logger (List l) a
  deriving (Eq, Show)

-- | Implement the `Functor` instance for `Logger
--
-- >>> (+3) <$> Logger (listh [1,2]) 3
-- Logger [1,2] 6
instance Functor (Logger l) where
  (<$>) :: (a -> b) -> Logger l a -> Logger l b
  f <$> (Logger ls x) = Logger ls (f x)

-- | Implement the `Applicative` instance for `Logger`.
--
-- >>> pure "table" :: Logger Int P.String
-- Logger [] "table"
--
-- >>> Logger (listh [1,2]) (+7) <*> Logger (listh [3,4]) 3
-- Logger [1,2,3,4] 10
instance Applicative (Logger l) where
  pure x = Logger Nil x
  (Logger ls f) <*> (Logger ls' x) = Logger (ls ++ ls') (f x)

-- | Implement the `Monad` instance for `Logger`.
-- The `bind` implementation must append log values to maintain associativity.
--
-- >>> (\a -> Logger (listh [4,5]) (a+3)) =<< Logger (listh [1,2]) 3
-- Logger [1,2,4,5] 6
instance Monad (Logger l) where
  (=<<) :: (a -> Logger l b) -> Logger l a -> Logger l b
  f =<< (Logger ls x) = appendLog ls (f x)
      where appendLog ls' (Logger ls'' y) = Logger (ls' ++ ls'') y

-- | A utility function for producing a `Logger` with one log value.
--
-- >>> log1 1 2
-- Logger [1] 2
log1 :: l -> a -> Logger l a
log1 e x = Logger (e :. Nil) x

-- | Remove all duplicate integers from a list. Produce a log as you go.
-- If there is an element above 100, then abort the entire computation and produce no result.
-- However, always keep a log. If you abort the computation, produce a log with the value,
-- "aborting > 100: " followed by the value that caused it.
-- If you see an even number, produce a log message, "even number: " followed by the even number.
-- Other numbers produce no log message.
--
-- /Tip:/ Use `filtering` and `StateT` over (`OptionalT` over `Logger` with a @Data.Set#Set@).
--
-- >>> distinctG $ listh [1,2,3,2,6]
-- Logger ["even number: 2","even number: 2","even number: 6"] (Full [1,2,3,6])
--
-- >>> distinctG $ listh [1,2,3,2,6,106]
-- Logger ["even number: 2","even number: 2","even number: 6","aborting > 100: 106"] Empty
distinctG
  :: (Integral a, Show a)
  => List a -> Logger Chars (Optional (List a))
  --  List a -> Optional (List a)
distinctG xs = runOptionalT $ fst <$> runStateT
        (filtering (\x ->
            StateT (\s ->
                OptionalT (if x <= 100 then
                    (if even x then log1 (fromString "even number") else pure) (Full (S.notMember x s, S.insert x s))
                    else log1 (fromString "abort") Empty))) xs) S.empty
