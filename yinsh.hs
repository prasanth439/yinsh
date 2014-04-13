module Yinsh where

import Haste
import Haste.Graphics.Canvas
import Data.List (minimumBy)
import Data.IORef

-- $setup
-- >>> import Data.List (sort, nub)
-- >>> import Test.QuickCheck
-- >>> let boardCoords = elements coords

-- Color theme
-- http://www.colourlovers.com/palette/15/tech_light
green = RGB 209 231  81
blue  = RGB  38 173 228
white = RGB 255 255 255

-- Dimensions
spacing         = 60 :: Double
markerWidth     = 20 :: Double
ringInnerRadius = 22 :: Double
ringWidth       = 6 :: Double
originX         = -15 :: Double
originY         = 140 :: Double

-- | Yinsh hex coordinates
type YCoord = (Int, Int)

data Direction = N | NE | SE | S | SW | NW deriving (Enum, Bounded)

-- | All directions
directions :: [Direction]
directions = [minBound .. maxBound]

-- | Vector to the next point on the board in a given direction
vector :: Direction -> YCoord
vector N  = ( 0,  1)
vector NE = ( 1,  1)
vector SE = ( 1,  0)
vector S  = (-1,  0)
vector SW = (-1, -1)
vector NW = (-1,  0)

-- | Player types: black & white or blue & green
data Player = B | W deriving Eq

-- | Next player
switch :: Player -> Player
switch B = W
switch W = B

-- | Translate hex coordinates to screen coordinates
screenPoint :: YCoord -> Point
screenPoint (ya, yb) = (0.5 * sqrt 3 * x' + originX, y' - 0.5 * x' + originY)
    where x' = spacing * fromIntegral ya
          y' = spacing * fromIntegral yb

-- could be generated by generating all triangular lattice points smaller
-- than a certain cutoff (~ 5)
numPoints :: [[Int]]
numPoints = [[2..5], [1..7], [1..8], [1..9],
             [1..10], [2..10], [2..11], [3..11],
             [4..11], [5..11], [7..10]]

-- | All points on the board
-- >>> length coords
-- 85
coords :: [YCoord]
coords = concat $ zipWith (\list ya -> map (\x -> (ya, x)) list) numPoints [1..]

-- | Check if two points are connected by a line
-- >>> connected (3, 4) (8, 4)
-- True
--
-- prop> connected c1 c2 == connected c2 c1
--
connected :: YCoord -> YCoord -> Bool
connected (x, y) (a, b) =        x == a
                          ||     y == b
                          || x - y == a - b

-- | List of points reachable from a certain point
--
-- Every point should be reachable within two moves
-- prop> forAll boardCoords (\c -> sort coords == sort (nub (reachable c >>= reachable)))
reachable :: YCoord -> [YCoord]
reachable c = filter (connected c) coords

-- | Vectorially add two coords
addC :: YCoord -> YCoord -> YCoord
addC (x1, y1) (x2, y2) = (x1 + x2, y1 + y2)

-- | Get all nearest neighbors
--
-- Every point has neighbors
-- >>> sort coords == sort (nub (coords >>= neighbors))
-- True
--
-- Every point is a neighbor of its neighbor
-- prop> forAll boardCoords (\c -> c `elem` (neighbors c >>= neighbors))
neighbors :: YCoord -> [YCoord]
neighbors c = filter (`elem` coords) adjacent
    where adjacent = mapM (addC . vector) directions c

-- | Get the coordinates of a players markers
markerCoords :: Board -> Player -> [YCoord]
markerCoords board p = [ c | Marker p' c <- board, p == p' ]

-- | Get all coordinates which are part of a combination of five
-- | connected markers
combinationCoords :: [YCoord] -> [YCoord]
combinationCoords b = []

-- | Get the five adjacent (including start) coordinates in a given direction
fiveAdjacent :: YCoord -> Direction -> [YCoord]
fiveAdjacent start dir = take 5 $ iterate (`addC` vector dir) start

-- | Test if A is subset of B
--
-- prop> x `subset` x     == True
-- prop> x `subset` (y:x) == True
subset :: Eq a => [a] -> [a] -> Bool
subset a b = all (`elem` b) a

-- | Get five adjacent marker coordinates, if the markers are on the board
maybeFiveAdjacent :: [YCoord] -> YCoord -> Direction -> Maybe [YCoord]
maybeFiveAdjacent list start dir = Just []

data DisplayState = BoardOnly GameState
                  | WaitTurn GameState

data Element = Ring Player YCoord
             | Marker Player YCoord

data TurnMode = AddRing
              | AddMarker
              | MoveRing YCoord
              | RemoveRing

type Board = [Element]

data GameState = GameState
    { activePlayer :: Player
    , turnMode :: TurnMode
    , board :: Board
    }

-- | All grid points as screen coordinates
points :: [Point]
points = map screenPoint coords

-- | Translate by hex coordinate
translateC :: YCoord -> Picture () -> Picture ()
translateC = translate . screenPoint

playerColor :: Player -> Color
playerColor B = blue
playerColor W = green

setPlayerColor :: Player -> Picture ()
setPlayerColor = setFillColor . playerColor

pRing :: Player -> Picture ()
pRing p = do
    setPlayerColor p
    fill circL
    stroke circL
    setFillColor white
    fill circS
    stroke circS
    pCross ringInnerRadius
        where circL = circle (0, 0) (ringInnerRadius + ringWidth)
              circS = circle (0, 0) ringInnerRadius

pMarker :: Player -> Picture ()
pMarker p = do
    setPlayerColor p
    fill circ
    stroke circ
        where circ = circle (0, 0) markerWidth

pElement :: Element -> Picture ()
pElement (Ring p c)   = translateC c $ pRing p
pElement (Marker p c) = translateC c $ pMarker p

pCross :: Double -> Picture ()
pCross len = do
    l
    rotate (2 * pi / 3) l
    rotate (4 * pi / 3) l
        where l = stroke $ line (0, -len) (0, len)

pDot :: Picture ()
pDot = do
    setFillColor $ RGB 0 0 0
    fill $ circle (0, 0) 5

pBoard :: Board -> Picture ()
pBoard board = do
    sequence_ $ mapM translate points (pCross (0.5 * spacing))
    -- sequence_ $ mapM (translate . screenPoint) (reachable (3, 6)) pDot
    mapM_ pElement board

pAction :: TurnMode -> YCoord -> Player -> Picture ()
pAction AddMarker mc p = pElement (Marker p mc)
pAction AddRing mc p = pElement (Ring p mc)

-- | Render everything that is seen on the screen
pDisplay :: DisplayState
         -> YCoord         -- ^ Coordinate close to mouse cursor
         -> Picture ()
pDisplay (BoardOnly gs) _ = pBoard (board gs)
pDisplay (WaitTurn gs) mc = pBoard (board gs) >> pAction (turnMode gs) mc (activePlayer gs)
-- pDisplay ConnectedPoints c = do
--     pBoard
--     sequence_ $ mapM (translate . screenPoint) (reachable c) pDot

-- | Get the board coordinate which is closest to the given screen
-- | coordinate point
--
-- prop> closestCoord p == (closestCoord . screenPoint . closestCoord) p
closestCoord :: Point -> YCoord
closestCoord (x, y) = coords !! snd lsort
    where lind = zipWith (\p i -> (dist p, i)) points [0..]
          lsort = minimumBy cmpFst lind
          dist (x', y') = (x-x')^2 + (y-y')^2
          cmpFst t1 t2 = compare (fst t1) (fst t2)

testBoard :: Board
testBoard = [
    Ring B (3, 4),
    Ring B (4, 9),
    Ring W (8, 7),
    Ring W (6, 3),
    Ring W (4, 8),
    Marker W (6, 4),
    Marker W (6, 5),
    Marker W (6, 7),
    Marker B (6, 6)]

testGameState = GameState {
    activePlayer = B,
    turnMode = AddMarker,
    board = testBoard
}

testDisplayState = WaitTurn testGameState

showMoves :: Canvas -> DisplayState -> (Int, Int) -> IO ()
showMoves can ds point = render can
                          $ pDisplay ds (coordFromXY point)

coordFromXY :: (Int, Int) -> YCoord
coordFromXY (x, y) = closestCoord (fromIntegral x, fromIntegral y)

main :: IO ()
main = do
    Just can <- getCanvasById "canvas"
    Just ce <- elemById "canvas"

    ioDS <- newIORef testDisplayState

    -- draw initial board
    render can (pBoard testBoard)

    ce `onEvent` OnMouseMove $ \point -> do
        ds <- readIORef ioDS
        showMoves can ds point

    ce `onEvent` OnClick $ \button point -> do
        modifyIORef' ioDS $ \(WaitTurn gs) ->
            WaitTurn (
                gs {
                    board = Marker (activePlayer gs) (coordFromXY point) : board gs,
                    activePlayer = switch (activePlayer gs)
                })
        return ()
    return ()
