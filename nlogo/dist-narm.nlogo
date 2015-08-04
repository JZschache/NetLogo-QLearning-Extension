extensions[ql matrix games]

turtles-own[ leader q-values total-n current-exp optimal-action last-field]
globals[ group-structure means-1-matrix means-2-matrix optimal-fields rel-freq-optimal]

to-report read-means-matrix [ nr ]
  let row-string-list []
  let temp means-x
  if (nr = 2) [set temp means-y]
  while [temp != ""] [
    let line-break position "\n" temp
    ifelse line-break = false [ 
      set row-string-list lput temp row-string-list
      set temp ""
    ] [
      set row-string-list lput (substring temp 0 line-break) row-string-list
      set temp substring temp (line-break + 1) (length temp)
    ]
  ]
  report (map [read-from-string (word "[ " ? " ]")] row-string-list)
end

to-report write-means-matrix [ matrix n-row ]
  let strings games:matrix-as-pretty-strings matrix
  let result ""
  foreach strings [ set result (word result (reduce [(word ?1 " " ?2 )] ?) "\n") ]
  report result
end


to set-game
  
  let rows1 (read-means-matrix 1)
  let rows2 (read-means-matrix 2)
  
  let pm1 games:matrix-from-row-list rows1
  let pm2 games:matrix-from-row-list rows2
  
  let game 0
  
  ifelse (game-name = "Custom") [
    set game games:two-persons-game pm1 pm2
  ] [
    ifelse (game-name = "CopyMeansX") [
      set pm2 pm1
      set game games:two-persons-game pm1 pm2
    ] [ 
      ifelse (game-name = "TransposeMeansX" and (length rows1) = (length first rows1) ) [
        set pm2 games:matrix-transpose pm1
        set game games:two-persons-game pm1 pm2
      ] [ ; use gamut    
        set game games:two-persons-gamut-game game-name n-alt-x n-alt-y
      ]
    ]
  ]
  
  set pm1 games:game-matrix game 1
  set pm2 games:game-matrix game 2
  let m games:matrix-as-pretty-strings pm1
  set n-alt-x length m
  set n-alt-y length first m
  
  set means-x write-means-matrix pm1 n-alt-x
  set means-y write-means-matrix pm2 n-alt-x
  
  set sample-equilibria games:get-solutions-string-with-expect game
  set fields games:get-fields-string game
  
end

to setup
  
  clear-all  
  
  let n-patches (1 + floor sqrt (n-pairs * 9))
  set-patch-size 400 / n-patches
  resize-world 0 n-patches 0 n-patches
    
  setup-all
  
  set group-structure []
    
  create-turtles n-pairs [
    set leader true
    setxy random-xcor random-ycor
    ; create a partner
    let partner 0
    hatch 1 [ 
      set leader false
      setxy (1 + [xcor] of myself) (1 + [ycor] of myself)
      set group-structure lput (ql:create-group (list self myself) (list (n-values n-alt-x [(word ?)]) (n-values n-alt-y [(word ?)]))) group-structure
      face myself
      set partner self
    ]
    face partner    
  ]
  
  ql:init turtles experimenting exploration
  ql:set-group-structure group-structure
  ql:decrease-experimenting experimenting-decay
  
  ask turtles [    
    set q-values ql:get-q-values
    set total-n ql:get-total-n
    set current-exp ql:get-experimenting
    set optimal-action one-of [true false]
  ]
  
  set rel-freq-optimal 0.5
  
  reset-ticks
end



to setup-all
  
  let rows1 read-means-matrix 1
  set means-1-matrix matrix:from-row-list rows1
  set n-alt-x length rows1
  set n-alt-y length first rows1
  let rows2 (read-means-matrix 2)
  set means-2-matrix matrix:from-row-list rows2
  
  let pm1 games:matrix-from-row-list rows1
  let pm2 games:matrix-from-row-list rows2
  
  let game games:two-persons-game pm1 pm2
  set optimal-fields games:game-pure-optima game
end

to-report get-reward [ env-id ]
  let dec-list ql:get-group-list env-id
  let result map [reward ?] dec-list
  report result
end

to-report reward [group-choice]
  let agents ql:get-agents group-choice
  let decisions ql:get-decisions group-choice
  
  let dec1 (read-from-string first decisions) 
  let dec2 (read-from-string last decisions)
  
  let field dec1 * n-alt-y + dec2 
  let optimal item field optimal-fields
  (foreach agents [ ask ?1 [ 
        set optimal-action optimal 
        set last-field field
     ]])
    
  let m1 matrix:get means-1-matrix dec1 dec2
  let m2 matrix:get means-2-matrix dec1 dec2
  let rewards (list (random-normal m1 sd) (random-normal m2 sd))
  let new-object ql:set-rewards group-choice rewards
  report new-object
end

to update
  
  let optimal-freq 0
  
  ask turtles [
     
    set q-values ql:get-q-values
    ;show q-values
    
    set total-n ql:get-total-n
    set current-exp ql:get-experimenting
    
    if leader [
      if optimal-action [ set optimal-freq optimal-freq + 1 ]
    ]
    
  ]
  
  set rel-freq-optimal optimal-freq / (n-pairs)
  
  tick
end
@#$#@#$#@
GRAPHICS-WINDOW
820
20
1234
455
-1
-1
4.2105263157894735
1
10
1
1
1
0
1
1
1
0
95
0
95
0
0
1
ticks
30.0

SLIDER
220
25
395
58
n-pairs
n-pairs
0
10000
1000
10
1
NIL
HORIZONTAL

BUTTON
820
460
970
493
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
820
495
970
528
NIL
ql:start
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
820
530
970
563
NIL
ql:stop
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
15
25
215
58
experimenting
experimenting
0
30
0.1
0.1
1
NIL
HORIZONTAL

SLIDER
400
25
575
58
sd
sd
0
10
1
0.1
1
NIL
HORIZONTAL

INPUTBOX
220
60
395
180
means-x
 0 10  0\n 0  0 10\n10  0  0\n
1
1
String

CHOOSER
15
95
215
140
exploration
exploration
"epsilon-greedy" "softmax"
0

MONITOR
15
305
215
350
NIL
rel-freq-optimal
2
1
11

MONITOR
1250
20
1540
65
NIL
ql:get-performance \"NLSuperBetweenTick\"
17
1
11

MONITOR
1250
70
1540
115
NIL
ql:get-performance \"NLSuperHandleGroups\"
17
1
11

MONITOR
1250
120
1540
165
NIL
ql:get-performance \"NLSuperGuiInter\"
17
1
11

PLOT
15
355
215
505
rel-freq-optimal
NIL
NIL
0.0
1.0
0.5
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot rel-freq-optimal"

SLIDER
15
60
215
93
experimenting-decay
experimenting-decay
0.9
1
1
0.001
1
NIL
HORIZONTAL

PLOT
15
145
215
295
experimenting
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "set-plot-y-range 0 experimenting" "plot mean [current-exp] of turtles"

INPUTBOX
220
355
765
505
fields
| 1: ( 0, 0)   | 2: (10, 0) P | 3: ( 0,10) P |\n| 4: ( 0,10) P | 5: ( 0, 0)   | 6: (10, 0) P |\n| 7: (10, 0) P | 8: ( 0,10) P | 9: ( 0, 0)   |\n
1
1
String

PLOT
15
510
215
660
fields-histogram
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 false "set-plot-x-range 0 (n-alt-x * n-alt-y)" "histogram [last-field] of turtles with [leader]"

INPUTBOX
400
60
575
180
means-y
 0  0 10\n10  0  0\n 0 10  0\n
1
1
String

CHOOSER
580
25
765
70
game-name
game-name
"Custom" "CopyMeansX" "TransposeMeansX" "BattleOfTheSexes" "Chicken" "CollaborationGame" "CoordinationGame" "DispersionGame" "GrabTheDollar" "GuessTwoThirdsAve" "HawkAndDove" "MajorityVoting" "MatchingPennies" "PrisonersDilemma" "RandomGame" "RandomZeroSum" "RockPaperScissors" "ShapleysGame"
16

BUTTON
580
145
765
178
NIL
set-game
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
220
185
765
346
sample-equilibria
    x1    x2    x3    y1    y2    y3  |    Ex    Ey  |    mx\n------------------------------------------------------------------\n   1/3   1/3   1/3   1/3   1/3   1/3  |  10/3  10/3  |     P\n
1
1
String

SLIDER
580
75
765
108
n-alt-x
n-alt-x
1
10
3
1
1
NIL
HORIZONTAL

SLIDER
580
110
765
143
n-alt-y
n-alt-y
1
10
3
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
1
@#$#@#$#@
