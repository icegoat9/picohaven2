--PICOhaven 2 
--by icegoat, Aug-Oct '23
--(sequel to PICOhaven https://www.lexaloffle.com/bbs/?tid=45105)

--This file is run through a script to strip comments and minify
-- variable names and then included by the main picohaven2.p8 cart, 
-- so these comments do not appear in the released cart

--see also picohaven2_source_doc.md as reference for
-- main state machine, sprite flags, and global variables

--Instructions, updates, and web-playable version:
-- https://www.lexaloffle.com/bbs/?tid=???ADDLINK???

--This file and related files and dev notes will be available in a
-- github repo: https://github.com/icegoat9/picohaven2

---- Code organization:
----- 1) core game init/update/draw
----- 2) main game state machine
----- 3) pre-combat states (new turn, choose cards, etc)
----- 4) action/combat loop
----- 4a) enemy action loop
----- 4b) player action loop
----- 5) post-combat states (cleanup, etc)
----- 6) main UI draw loops and card draw functions
----- 7) custom sprite-based font and print functions
----- 8) menu-draw and related functions
----- 9) miscellaneous helper functions
----- x) pause menu items [deprecated]
----- 10) data string -> datastructure parsing + loading
----- 11) inits and databases
----- 12) profile / character sheet
----- 13) splash screen / intro
----- 14) levelup, upgrades
----- 15) town and retirement
----- 16) debugging + testing functions
----- 17) pathfinding (A*)
----- 18) load/save


-- 
--                 PICOhaven game state machine
-- 
-- 
--                +-------------+ continue game                    +-----------+    +-------------+
--                | splash      +---------------------------------->           +----> retire*     |
--                +-----+-------+                                  |           |    +-------------+
--                      |new game      +---------------------------+   town    |
--                +-----v-------+      |                           |           |    +-------------+
--                | newlevel    +------+          +---------------->           +----> upgradedeck |
--                +-----+-------+                 |                +-^---^---^-+    +------+------+
--                      |                   +-----v------+           |   |   |             |
--                      |                   | pretown    |   +-------v-+ |   |      +------v------+
--                +-----v-------+           +-----^------+   | profile | |   +------+ upgrademod  |
--                | newturn     <--------+        |          +---------+ |          +-------------+
--                +-+-------^---+        |  +-----+------+               |
--                  |       |review map  |  | endoflevel |           +---v---+
--                +-v-------+---+        |  +-----^------+           | store |
--                | choosecards |        |        |                  +-------+
--                +-----+-------+        |  +-----+------+
--                      |                +--+ cleanup    <--------------+
--                      |                   +------------+              |
--                +-----v-------+                               +-------+--------+
--                | precombat   +------------------------------->                |
--                +-------------+                               |    actloop     |
--                                                  +----------->                <-----+
--                                                  |           +--+----------+--+     |
--                                                  |              |          |        |done
--                                                  |   +----------v---+   +--v--------+--+
--                                                  |   | actplayerpre |   | actenemy     |
--                                                  |   +---+----------+   +-------^------+
--                                              done|       |                      |move
--                                               +--+-------v---+          +-------v------+
--                                    +----------> actplayer    <----------+              |
--                                    |          |              |          | animmovestep |
--                                    |       +-->              <--+       |              |
--                                    |       |  +--+--------+--+  |       +--^--------^--+
--                                done|   undo|     |        |     |undo      |        |
--                                  +-+-------+-----v--+  +--v-----+------+   |        |
--                                  | actplayerattack  |  | actplayermove +---+        |
--                                  +---------+--------+  +---------------+            |
--                                        push|                                        |
--                                            +----------------------------------------+

-- custom font used as game icons cheatsheet:
--  shift + letter in pico8 font (replaced by custom font in game)
--   a█b▒c🐱d⬇️e░f✽g●h♥i☉j웃k⌂l⬅️m😐n♪o🅾️p◆q…r➡️s★t⧗u⬆️vˇw∧x❎y▤z▥      
--   (shift+a = █, used to represent attack, shift+b=▒=burn, etc )
--  hiragana characters also used for some icons (w/ custom font)
--   aあiいuうeえoお kaかkiきkuくkeけkoこ saさsiしsuすseせsoそ

--some general config for shrinko-8 minifier (see also --lint prefixes to functions)
-- a few key variable names to not rename/minify, to simplify runtime debugging
--preserve: dlvl,state,actor,mvq,msgq,p,p_xp,p_gp,pdeck,tpdeck,edecks,pitems,mapmsg,wongame,lvls,dset2,dget2,msg_yd

-----
----- 1) core game init/update/draw functions, including animation queue
-----

function _init()
  --debugmode=false
  --logmsgq=true
  --if (logmsgq) printh('\n*** new cart run ***','msgq.txt')

  --  godmode=true --power up character for debugging and rapid play-through testng
  dlvl=2  --starting dungeon #
  --  stop("level debug mode.\ntype 'dlvl=##' to set level, then 'resume'")
  
  initfont()
  initglobals()
  initdbs()
  initpersist()
  --interpret pink (color 14) as transparent for sprites, black is not transparent
  palt(0b0000000000000010)
  music(0)
  changestate("splash")
end

function _draw()
  --if wipe>0, a "screenwipe" is in progress, only update part of screen
  local s=128-2*wipe
  clip(wipe,wipe,s,s)
  _drwstate() --different function depending on state, set by state's init fn
  clip()
  
  --debugging routine for displaying performance / cpu usage across various parts of code
  --if using, need to umcomment statstr= and addstat1() related code elsewhere
--  print("\#a"..stat(7).."fps "..predrawstat1..","..(stat(1)*100\1)..","..stat(2).."%cpu",0,0,1)
--  addstat1()
--  print(statstr,0,0,1)
end

--lint:shake,msgreview,_updprev
function _update60()
--  statstr="\#a" --debug stat(1) usage string
  if animt<1 then
    --if a move/attack square-to-square animation is in progress,
    -- only update that frame by frame until complete
    _updonlyanim()
  else
    --normal update routine
    shake=0  --turn off screenshake if it was on (e.g. due to "*2" mod card drawn)
    --move killed enemies off-screen (but only once any attack animations 
    -- being processed via _updonlyanim() have completed)
    -- (they will then be deleted from actor[] at end of turn)
    for a in all(actor) do
      if (a.hp<=0 and a!=p) a.x=-99
    end
    _updstate() --different function depending on state, set by state's init fn
  end
  _updtimers()
end

--regardless-of-state animation updates:
-- update global timer tick, animation frame, screenwipe, message scrolling
--lint: msgpause
function _updtimers()
  --common frame animation timer ticks
  fram+=1
  afram=flr(fram/act_td)%4
  --if screenwipe in progress, continue it
  wipe=max(0,wipe-5)
  --every msg_td # of frames, scroll msgbox 1px
  --msgq auto-scrolls (even in review mode), until player
  -- presses up arrow (see _updscrollmsg() which sets msgpause)
  if fram % msg_td==0 and #msgq>3 and msg_yd<(#msgq-3)*6 and not msgpause then
      msg_yd+=1
  end
end

--run actor move/attack animations w/o user input until done
-- kicked off by setting common animation timer animt to 0
-- this function then gradually increases it 0->1 (=done)
function _updonlyanim()
  animt=min(animt+animtd,1)
  for a in all(actor) do
    --pixel offsets to draw each sprite at relative to its 8*x,8*y starting location
    a.ox,a.oy=a.sox*(1-animt),a.soy*(1-animt)
    if animt==1 then
      a.sox,a.soy=0,0
      --delete ephemeral 'actors' that are not really player/enemy actors (e.g. "damage number" sprites)--
      -- they were only created and added to actor[] to reuse this code to animate them
      if (a.ephem) del(actor,a)
    end
  end
end

-----
----- 2) main game state machine
-----

--the core of the state machine is to call changestate() rather
-- then directly edit the 'state' variable. this function calls
-- a relevant init() function (which updates update and draw functions)
-- and resets some key globals to standard values to avoid need
-- to reset them in every state's init function
--lint: selx,sely,seln,msg_x0,msg_w,selvalid,showmapsel
function changestate(_state,_wipe)
  prevstate=state
  state=_state
  selvalid,showmapsel=false,false
  selx,sely,seln=1,1,1
  setprompt()
  --screen wipe on every state change, unless passed _wipe==0
  wipe = _wipe or 63
  --reset msgbox x + width to defaults
  msg_x0,msg_w=0,map_w
  --run specific init function defined in initglobals()
  if (initfn[_state]) initfn[state]()
end

-- a simple wait-for-🅾️-to-continue loop used as update in various states
function _upd🅾️()
  ---if (showmapsel) selxy_update_clamped(10,10,0,0)
  if (btnp(🅾️)) changestate(nextstate)
end

-----
----- 3) the "pre-combat" states
-----

---- state: new level

--lint: mapmsg
function initnewlevel()
  initlevel()
  --play theme music, though don't restart music if it's already playing from splash screen
  --if (prevstate!="splash") music(0)
  mapmsg=pretxt[dlvl]
  setprompt("\fc🅾️\f6:bEGIN")
  nextstate,_updstate,_drwstate="newturn",_upd🅾️,_drawlvltxt
end

--display the pre- or post-level story text in the map frame
--TODO? merge into drawmain (since similar) + use a global to set whether map or text is displayed
--      but: that would become less clear, might only save ~15tok
function _drawlvltxt()
  clsrect(0)
  drawstatus()
  drawmapframe()
  printwrap(mapmsg,21,4,10,6)
  drawheadsup()
  drawmsgbox()
end

---- state: new turn

function initnewturn()
  --purge all but the last N elements of previous turns' msgq (hardcoded to save tokens)
  -- to avoid slowdowns seen especially if #msgq > 100 items
  --TODO? could in future save tokens by removing this and returning to resetting
  -- the queue every turn rather than only in initlevel()
  while #msgq>30 do
    deli(msgq,1)
    msg_yd=max(0,msg_yd-6) --move msg pointer up a line of pixels at the same time
  end
  addmsg("\f7----- nEW rOUND ------")
  setprompt("\fcさし\f6:iNSPECT mAP  \-f🅾️\f6:cARDS")
  selx,sely,showmapsel=p.x,p.y,true
  _updstate,_drwstate=_updnewturn,_drawmain
end

function _updnewturn()
  selxy_update_clamped(10,10,0,0)  --11x11 map
  if (btnp(🅾️)) changestate("choosecards")
end

--shared function used in many states to let player use
-- arrows to move selection box in x or y, clamped to an allowable range
function selxy_update_clamped(xmax,ymax,xmin,ymin)
  --sets default xmin,ymin values of 1 if not passed to save a
  -- few tokens by omitting them in function calls (this is why they are
  -- listed last as function parameters, so they'll default to nil if omitted)
  --this approach is used widely in code to set default parameters
  --TODO? if we could allow a default xmin and ymin of 0, we could save a few tokens
  -- by eliminating the following line since mid() assumes nil parameters are 0
  -- but Lua is 1-indexed so min values of 1 are simpler elsewhere
  xmin,ymin = xmin or 1, ymin or 1
  --loop checking which button is pressed
  for i=1,4 do
    if btnp(i-1) then
      selx+=dirx[i]
      sely+=diry[i]
      break --only allow one button to be enabled at once, no "diagonal" moves
    end
  end
  --clamp to allowable range
  selx,sely=mid(xmin,selx,xmax),mid(ymin,sely,ymax)
  --item #n in an x,y grid of items
  --TODO?: also clamp seln to a max value? (not currently needed)
  seln=(selx-1)*ymax+sely
end

---- state: choose cards

--lint: tpdeck
function initchoosecards()
  --create a semi-local copy of pdeck (that adds the "rest"
  -- and "confirm" virtual cards that aren't in deck and shouldn't
  -- show up in character profile view of decklist)
  tpdeck={}
  for crd in all(pdeck) do
    add(tpdeck,crd)
  end
  --add "long rest" card (see init fns)
  refresh(longrestcrd)
  add(tpdeck,longrestcrd)
  --add "confirm" option, implemented as a card
  add(tpdeck,splt("act;confirm;status;1;name;\nconfirm\n\n\f6confirm\nthe two\nselected\ncards",false,true))
  setprompt("\fc🅾️\f6:sELECT 2 cARDS \fc❎\f6:mAP")
  p.crds={}
  _updstate,_drwstate=_updhand,_drawhand
end

--"selecting cards from hand" update function
function _updhand()
  selxy_update_clamped(2,(#tpdeck+1)\2)
  --if tpdeck has an odd number of cards, don't let selector move
  -- to the unused (bottom of column 2) location
  --TODO? build this into selxy_update_clamped() instead
  --      (but only used in this one location, not worth the abstraction?)
  if (seln>#tpdeck) sely-=1

  if tutorialmode then
    local promptstr=splt("\fcさし🅾️\f6:sELECT 1ST CARD;\fcさし🅾️\f6:sELECT 2ND CARD;\fcさし🅾️\f6:\f7confirm\f6 IF DONE")
    setprompt(promptstr[#p.crds+1])
  end

  if btnp(🅾️) then
    local selcrd=tpdeck[seln]
    --status (0=in hand, 1=discarded, 2=burned)
    if selcrd.status==0 then
      --card not discarded/burned, can select
      if indextable(p.crds,selcrd) then
        --card was already selected: deselect
        del(p.crds,selcrd)
      else
        --select card
        if selcrd.act=="rest" then
          --clear other selections
          p.crds={}
        end
        if seln==#tpdeck then 
          --if last entry "confirm" selected, move ahead with card selection
          -- NOTE: that "confirm" can only be selected if it is enabled
          -- (card.status==0), which is only set if 2 cards are selected
          --set these cards to 'discarded' now even before we get to playing them
          -- (so a "burn random undiscarded card to avoid damage"
          -- trigger before player turn can't use them)
          for c in all(p.crds) do
            c.status=1
          end
          pdeckbld(p.crds)
          changestate("precombat")
        elseif #p.crds<2 then
          --if a new card is selected (and <2 already selected)
          add(p.crds,selcrd)
        end
      end
      --enable "confirm" button if and only if 2 cards selected,
      -- otherwise set it to "discarded" mode to grey it out
      tpdeck[#tpdeck].status = #p.crds==2 and 0 or 1
    end
  elseif btnp(❎) then
    -- review map... by jumping back to newturn state
    changestate("newturn")
  end
end

function _drawhand()
  clsrect(5)
  print("\f6yOUR dECK:\n\n\n\n\n\n\n\n\n\n\n\n\n\*f \*7 \+celEGEND:",8,24)
  drawcard("discard",92,108,1)
  drawcard("burned",92,118,2)
  --split deck into two columns to display
  local tp1,tp2=splitarr(tpdeck)
  drawcardsellists({tp1,tp2},0,27,p.crds,9)
  --tip on initiative setting
  if (#p.crds<1) printmspr("\f61ST cARD CHOSEN\nSETS \f7iNITIATIVE,\f6\nlOW:aCT fIRSTす",61,3)
  --drawmsgbox()  --commented out to eliminate msgbox in drawhand mode, just use single-line prompt
  drawprompt()
end

--create list of options-for-turn to display on player
-- box in HUD, from selected cards
--lint: restburnmsg
function pdeckbld(clist)
  --if first card is "rest", only play that and burn other
  if clist[1].act=="rest" then
    --message will be displayed later in turn, when you play rest
    restburnmsg="\f8burned\f6 ["..clist[2].act.."]"
    clist[2].status=2
    deli(clist,2)
  else
    --add default alternate actions 😐2/█2 to options for turn
    -- (unless certain items held that modify these)
    local defmove=hasitem("swift") and "😐3" or "😐2"
    --TODO: comment out below testing-only hack to give powerful default move
    --local defmove=hasitem("swift") and "😐8" or "😐5웃"
    if (hasitem("belt")) defmove..="웃"
    add(clist,{act=defmove})

    add(clist,{act=hasitem("quivr") and "█2➡️3" or "█2"})
    --TODO: comment out below testing-only hack w/ powerful defaults
    --add(clist,{act=hasitem("quivr") and "█2➡️3" or "█0◆3"})
  end
end

---- state: precombat
--lint: initi
function initprecombat()
  --draw enemy cards for turn
  selectenemyactions()
  --ilist[]: global sorted-by-initiative list of actors
  --initi: "who in ilist[] is acting next"?
  ilist,initi=initiativelist(),1

  --TODO: decide if these tutorial tips are worth all the tokens / redundancy
  local msg="🅾️:bEGIN tURNS"
  if tutorialmode then
    msg="🅾️:bEGIN  ("..ilist[1].name.." FIRST @iNIT \f7"..ilist[1].init.."\f6)"
  end
  setprompt(msg)
  nextstate,_updstate,_drwstate="actloop",_upd🅾️,_drawmain
end

--draw random action card for each enemy type and set
-- relevant global variables to use this turn
function selectenemyactions()
  local etypes=activeenemytypes()
  for et in all(etypes) do
    et.crds = rnd(edecks[et.id])
    et.init = et.crds[1].init
  end
  for a in all(actor) do
    --add link to crds for each individual enemy
    --TODO: rethink this and remove redundancy of both enemy type and enemy
    --      having .init and .crds, but complicated by player not 
    --      having a .type (enemy type)
    if (a.type) a.crds=a.type.crds
    a.init=a.crds[1].init
    a.crdi=1  --index of card to play next for this enemy
  end
end

--generate list of active enemy types (link to enemytype[] entries)
-- from list of actors (only want one entry per type even if many instances of an enemy type)
function activeenemytypes()
  local etypes={}
  for a in all(actor) do
    if (a!=p and not(indextable(etypes,a.type))) add(etypes,a.type)
  end
  return etypes
end

-----
----- 4) the "actor action" / combat states
-----

---- NOTE: see picohaven2_source_doc.md for a diagram of the
----       state machine: many interconnected actionloop states

---- general action loop state (which will step through each actor, enemy and player)

function initactloop()
  _updstate=_updactloop
  _drwstate=_drawmain   --could comment out to save 3 tokens since hasn't changed since last state (but that's risky/brittle to future state flow changes)
end

--each time _updactloop() is called, it runs once and
-- dispatches to a specific player or enemy's action function (based on value of initi)
--lint: actorn
function _updactloop()
  if p.hp<=0 then
    loselevel()
    return
  end
  if initi>#ilist then
    --all actors have acted
    changestate("cleanup",0)
    return
  end
  actorn=ilist[initi].id  --current actor from ordered-by-initiative list
  local a=actor[actorn]
  --increment index to actor, for the _next_ time this  function runs
  initi+=1
  --if actor dead, silently skip its turn 
  if (a.hp<1) return  
  --below tutorial note commented out to save ~20tokens
  --if (tutorialmode) addmsg("@ initiative "..ilist[initi-1][1]..": "..a.name)
  if a==p and p.crds[1]==longrestcrd then
    --special case: long rests always run (even if stunned), w/o player interaction needed
    longrest()
    --in case player stunned. TODO? move this line into longrest()
    p.stun=nil   
  elseif a.stun then 
    --skip turn if stunned
    addmsg(a.name.." ▥, TURN SKIPPED")
    a.stun=nil
  else
    if (a==p) then
      changestate("actplayerpre",0)
    else
      changestate("actenemy",0)
    end
  end
end

-----
----- 4a) the enemy action loop states
-----

---- state: actenemy

function initactenemy()
  _updstate=_updactenemy
  _drwstate=_drawmain   --could comment out to save 3 tokens since hasn't changed since last state (but that's risky/brittle to future state flow changes)
end

--execute one enemy action from enemy card
--(will increment global actor.crdi and run this multiple times if enemy has multiple actions)
function _updactenemy()
  local e=actor[actorn]
  --if all cards played, done, advance to next actor
  if e.crdi>#e.crds then
    changestate("actloop",0)
    return
  end
  --generate current "card to play"'s data structure, set global e.crd
  e.crd=parsecard(e.crds[e.crdi].act)
  --advance index for next time
  e.crdi+=1
  if e.crd.act=="😐" then
    --if current action is a move, and enemy will have a ranged attack as the following action,
    -- store that attack range so move can stop once it's within range
    --NOTE: crdi below now refers to the 'next' card because of the +=1 above
    if e.crdi<=#e.crds then
      local nextcrd=parsecard(e.crds[e.crdi].act)
      if (nextcrd.act=="█") e.crd.rng=nextcrd.rng
    end
  end
  runcard(e)  --execute specific enemy action
end

-- actor "a" summons its summon (and loses 2 hp)
-- (written for only enemy summoning, but could be extended for player summons in future chapter of game)
function summon(a)
  local smn=a.type.summon
  local neighb=valid_emove_neighbors(a,true) --valid adjacent squares to summon into
  if #neighb>0 then
    local smnxy=rnd(neighb)
    initenemy(smn,smnxy.x,smnxy.y)
    addmsg(a.name.." \f7SUMMONS\f6 "..enemytype[smn].name..",\f8-2♥\f6")
    --hard-coded that summoning always inflicts 2dmg to self
    dmgactor(a,2)
  end
end

-- moderately complex process of pathfinding for enemy moves (many sub-functions called)
function enemymoveastar(e)
  --basic enemy A* move, trimmed to allowable move distance:
  mvq = trimmv(pathfind(e,p),e.crd.val,e.crd.rng)
  --if no motion would happen via the normal "can pass thorugh allies" routing,
  -- enemy could be stuck behind one of its allies-- in this case, try routing 
  -- with "allies block motion" which may produce a useful "route around" behavior
  if not mvq or #mvq<=1 then
    mvq = trimmv(pathfind(e,p,false,true),e.crd.val,e.crd.rng)
  end
  --animate move until done (then will return to actenemy for next enemy action)
  changestate("animmovestep",0)
end

--trim down an ideal unlimited-steps enemy move to a goal, 
-- by stopping once either enemy is within
-- range (with LOS) or enemy has used up move rating for turn
function trimmv(_mvq,mvval,rng)
  if (not _mvq) return _mvq
  local trimto
  for i,xy in ipairs(_mvq) do
    local v=validmove(xy.x,xy.y,true)
    if i==1 or v and i<=(mvval+1) then  --equivalent to 'i==1 or (v and ...)'
      trimto=i
      --if xy is within range (1 unless ranged attack) and has LOS, trim here, skip rest of for loops
      if (dst(xy,p)<=rng and lineofsight(xy,p)) break
    end
  end
  return {unpack(_mvq,1,trimto)}
end

-- --WIP more complex pathfinding algorithm (on hold for lack of code
-- --    space / tokens, and current draft is buggy)
-- --Plan A* moves to all four cells adjacent to player, determine which of these
-- -- moves is 'best' (if none are adjacent or in range of a ranged attack, which
-- -- partial move ends with the shortest path to the player in a future turn?)
--function enemymoveastaradvanced(e)
--  --bug: this routing allows enemy to move _through_ player to an open spot on other side
--  --minor bug: enemies don't always route around
--  --This is ~50 tokens more than a simpler single A* call
--  local potential_goals=valid_emove_neighbors(p,true)
--  bestdst,mvq=99,{}
--  for goal in all(potential_goals) do
--    local m=find_path(e,goal,dst,valid_emove_neighbors)
--    m=trimmv(m,e.crd.val,e.crd.rng)
--    if m then --if non-nil path returned
--      --how many steps would it take from this path's
--      -- endpoint to reach player in future?
--      local d=#find_path(m[#m],p,dst,valid_emove_neighbors)
--      if d<bestdst then
--        bestdst,mvq=d,m
--      end
--    end
--  end
--  changestate("animmovestep",0)
--end

-- general "valid move?" function for all actors
function validmove(x,y,endat,jmp,actornum,allyblocks)
  --endat: if true, validate ending at this
  --       spot (otherwise checking pass-through)
  --jmp: jumping (can pass over some obstacles and enemies if not ending at this location)
  --allyblocks: do enemies' allies block their movement?
  --            (by default enemies can pass through though not end moves on allies)
  --actornum: actor[] index of moving actor (1: player)

  --unjumpable obstacles (walls, fog)
  if (fget(mget(x,y),1) or isfogoroffboard(x,y)) return false
  --obstacle w/o jump (or even w/ jump can't end at)
  if (fget(mget(x,y),2) and (endat or not jmp)) return false
  --can't walk through actors, except enemies through their allies
  -- or jumping past them
  local ai=actorat(x,y)
  --can't end on actor (except, actors can end of self i.e. 0 move)
  if (endat and ai>0 and actornum!=ai) return false
  --by default, enemies can pass through allies
  -- (unless we pass the 'ally blocks moves' flag,
  --  used to break out of some routing deadlocks)
  if ((allyblocks or actornum==1) and ai>1 and not jmp) return false
  return true
end

-- return list of "valid-move adjacent neighbors to (node.x,node.y)"
-- used in A* pathfind(), for example
function valid_emove_neighbors(node,endat,jmp,allyblocks)
  --see parameter descriptions in validmove()
  local neighbors = {}
  for i=1,4 do
    local tx,ty=node.x+dirx[i], node.y+diry[i]
    if validmove(tx,ty,endat,jmp,nil,allyblocks) then
      add(neighbors, xylst(tx,ty))
    end
  end
  return neighbors
end

----wrapper to above allowing jmp, to pass to A* pathfind
----Note: moved to inline anonymous function since only used once in program
--function valid_emove_neighbors_jmp(node)
--  return valid_emove_neighbors(node,false,true)
--end

----wrapper allowing enemies to move through allies, for A* calls
----Note: moved to inline anonymous function since only used once in program
--function valid_emove_neighbors_allyblocks(node)
--  return valid_emove_neighbors(node,false,false,true)
--end

--execute attack described in attacker's card a.crd, against defender d
--lint:apushed,aoe_xy_center,pushdmg,apushedinto,pushblockx,pushblocky
function runattack(a,d)
  --a = attacker, d = defender (in actor[] list)
  local crd=a.crd
  --save values before modifier card drawn
  local basewound=crd.wound
  --local basestun=crd.stun --TODO: check that no mod cards set stun...
  local dmg=crd.val
  local msg=""
  --draw attack mod card (currently player-only)
  if a==p then
    local mod=drawmodcard()
    -- TODO? restore or remove these old more verbose PICOhaven 1 mod card messages
    --if (tutorialmode) addmsg("yOU DRAW mODIFIER \f7"..mod)
    if (tutorialmode) addmsg("yOU DRAW RANDOM\n mODIFIER CARD \f7"..mod)
    msg="\f7["..mod.."\f7]\f6 \-f"
    if mod=="*2" then
      dmg*=2
      shufflemoddeck()
      shake=3 --screenshake of 3 pixels to emphasize drawing of *2 card
    elseif mod=="/2" then
      dmg\=2
      shufflemoddeck()
    else
      --check for mod card conditions
      if mod[-1]=="∧" then
        crd.wound=true
        mod=sub(mod,1,#mod-1)
      ----TODO: remove this stun-handling code if no mod cards add stun
      --elseif mod[-1]=="▥" then
      --  crd.stun=true
      --  mod=sub(mod,1,#mod-1)
      end
      --modify damage via mod
      --avoid negative damage. some duplicate tokens with
      -- max(0,dmg) below, but this is needed so that the
      -- msg..= cmd in shld area below reads right in 
      -- if there's "negative damage" pre-shield 
      dmg=max(0,dmg+tonum(mod))
    end
  end
  -- below runs for all actors
  sfx(1)
  -- do damage and effects
  msg..=a.name.."█"..d.name
  if d==p and hasitem("shld",true) then
    p.shld+=2
    addmsg("\f7gREAT sHIELD USED\f6:+★2")
  end
  if d.shld>0 then
    msg..="("..d.shld.."★)"
    dmg=dmg-d.shld
  end
  dmg=max(0,dmg)
  msg..=":\f8-"..dmg.."♥\f6"
  if a.crd.stun then
    msg..="▥"
    d.stun=true
  end
  if a.crd.wound then
    msg..="∧"
    d.wound=true
  end
  --push attack (but don't push if it was a killing blow)
  if a.crd.push and d.hp>dmg then 
    --build push move queue, starting with defender current loc
    --msg..="◆"
    mvq={xylst(d.x,d.y)}
    for i=1,a.crd.push do
      --"d.x-a.x" is push_deltax: direction of push
      local tx,ty=d.x+i*(d.x-a.x),d.y+i*(d.y-a.y)
--      stop("can we push to "..tx..","..ty.."?") --debug message
      if validmove(tx,ty,true) then
        add(mvq,xylst(tx,ty))
--        stop("yes, added to mvq as#"..#mvq) --debug message
      else
--        stop("no, obstacle") --debug message
          --queue up damage at end of move animation in initanimmovestep()
          pushdmg=i  
          --actor on the receiving end of a push collision, if any
          -- (will be 0 if not)
          apushedinto=actor[actorat(tx,ty)]
          pushblockx,pushblocky=tx,ty --globals for an animation
--        end
        
        break --don't move past obstacle
      end
    end
    --execute push itself below (after damaging actor)
  end
  --reset card .stun and .wound-- only relevant if a
  -- multi-target attack AND .stun/.wound were applied
  -- by a modifier card (so should not necessarily be
  -- applied ot all targets)
  crd.wound=basewound
  --crd.stun=basestun  --commented out since no mod cards set stun...
  addmsg(msg)
  --prepare attack animation
  local aspr=144+dmg
  if (dmg>9) aspr=154
  queueanim(nil,d.x,d.y,a.x,a.y,aspr)
  dmgactor(d,dmg)
  --if we'll push at least one square w/ a push action
  --checking "a.crd.push" may be unneeded, it's to avoid false triggers
  -- just in case mvq still exists from another routine and wasn't
  -- cleared (commenting out for now, but has some bug risk...)
--  if a.crd.push and #mvq>1 then
  if #mvq>=1 then
    apushed=d --global, tells animmovestep non-active actor is moving
    changestate("animmovestep",0)
  end  
end

--draw player attack modifier card
-- (and maintain a discard pile and dwindling deck)
function drawmodcard()
  if #pmoddeck==0 then
    shufflemoddeck()
  end
  local c = rnd(pmoddeck)
  add(pmoddiscard,c)
  del(pmoddeck,c)
  return c
end

--try to have enemy attack
function enemyattack(e)
  if dst(e,p) <= e.crd.rng and lineofsight(e,p) then
    runattack(e,p)
  end
end

function healactor(a,val)
  local heal=min(val,a.maxhp-a.hp)
  a.hp+=heal
  if (heal>0 or a.wound) addmsg(a.name.." hEALED \f8+"..heal.."♥")
  a.wound=nil
end

--damage actor and check death, etc
function dmgactor(a,val)
  a.hp-=val
  if a.hp<=0 then
    if a==p then
      --TODO? (tbd draft): shift to new more frantic music for rest of level. 
      --      ideally check if we've already done this to avoid music restart...
      --      if used, would need to reset neardeath=false in initlevel()
      --      could also only trigger this on burned card subset of conditions to avoid trigger before actual death
      --      alternately, this could just call a special SFX (only 3 tokens) rather than new music
      --if not neardeath then
      --  neardeath=true
      --  music(foo)
      --end
      if hasitem("life",true) then
        a.hp,a.wound=1,false
        addmsg("\f7yOUR lIFE cHARM GLOWS\n AND YOU SURVIVE @ 1hp")
      else
        -- burn random card in hand to negate dmg
        local crd=rnd(cardsleft())
        if crd then
          crd.status=2
          a.hp+=val
          addmsg("yOU \f8bURN\f6 A RANDOM CARD\n\f8[\f6"..crd.act.."\f8]\f6 \-fTO AVOID DEATH")
        end
      end
      --player near-death sound effect
      sfx(3)
    else
      addmsg(""..a.name.." IS dEFEATED!")
      --sfx(2)
      if a.name=='orb' then
        --as each orb is broken, reduce boss shield
        local boss=actor[indextable(actor,"noah","name")]
        --TODO? (tbd): could save a few tokens by removing this "if boss"
        --  check, which guards against a very unlikely no-boss-exists crash bug
        --  where player kills boss earlier in round, then also kills an
        --  orb later that round before victory triggers
        if boss then
          boss.pshld\=2
          boss.shld\=2 --otherwise won't happen until end of turn cleanup's shld=pshld
          addmsg("\fcnOAH HOWLS AS THE AURA\n\fc AROUND HIM WEAKENS..")
        end
      end
      --clear move queue: should only be relevant if actor was in
      -- the middle of moving or being pushed when it hit a trap
      -- and died: we want to abort the moving animation
      mvq={}
      --drop coin (except for "object" enemies like gravestones and orbs), 
      -- note: coin won't be visible until check in _update60() removes
      -- enemy sprite from play area
      if not a.obj then
        --TODO? comment out this tutorial line to save tokens, unnecessary
        if (tutorialmode) addmsg(" AND DROPS gOLD (●)")
        local m=mget(a.x,a.y)
        local cspr=13 --coin sprite
        -- if there's already 1 or 2 coins on this space, update to 
        --  the sprite that indicates a 2-3 coin stack (dropping >3 coins
        --  on the same location should be rare, in those cases it maxes
        --  out as a 3-coin stack)
        if m>=13 and m<=15 then 
          cspr=min(15,m+1)
        elseif m!=33 then
          --if it's not a blank space or coin already, abort and don't
          -- drop gold (don't overwrite an herb or other campaign object)
          cspr=m
        end
        mset(a.x,a.y,cspr)  
      end
      p_xp+=1
      camp_kills+=1 --campaign stat
    end
  end
end

-----
----- 4b) player actions
-----

--first time entering actplayer for turn
function initactplayerpre()
  p.actionsleft=2
  changestate("actplayer",0)
end

--each time entering actplayer (typically runs twice/turn,
-- for 1st + 2nd actions fof turn, but also runs after 'undo', etc)
function initactplayer()
  --checks for ended-on-trap-with-jump-on-prev-move,
  -- since that wouldn't be caught during animmovestep
  checktriggers(p)
  if (p.actionsleft == 0) then
    p.crds,p.init=nil  --assignment with misssing values sets p.init to default of nil
    changestate("actloop",0)
    return
  end
  --setprompt("\fcし🅾️\f6:cHOOSE cARD "..3-p.actionsleft)
  --setprompt("\fcし🅾️\f6:choose card or dflt")
  setprompt(tutorialmode and "\fcし🅾️\f6:card (OR dFLT █2😐2)" or "\fcし🅾️\f6:cHOOSE cARD "..3-p.actionsleft)
  _updstate=_updactplayer
  _drwstate=_drawmain   --could comment out to save 3 tokens since hasn't changed since last state (but that's risky/brittle to future state flow changes)
end

--loops in this routine until card selected and 🅾️, then runs that card
-- (and then the called function typically changes state to actplayer 
--  when done, to rerun initactplayer above before running this again)
--lint: crdplayed,crdplayedpos
function _updactplayer()
  selxy_update_clamped(1,#p.crds) --let them select one of p.crds
  if btnp(🅾️) then
    --crd = the card table (has .init, .act, .status, .name)
    --note: if card in players deck, this is a reference to an entry in pdeck
    --      so edits to crd (e.g. changing crd.status to discard or burn it) also edit the original in pdeck for future turns
    local crd=p.crds[sely]
    --global copy to restore if needed for an undo
    crdplayed,crdplayedpos=crd,indextable(p.crds,crd)
    --parse just the action string into data structure
    p.crd=parsecard(crd.act)
    --special-case modification of range, dmg based on items
    if p.crd.rng and p.crd.rng>1 then
      if (hasitem("goggl")) p.crd.rng+=3
      --we know val is dmg if it's a ranged card
      if (hasitem("razor")) p.crd.val+=1
    end    
    p.actionsleft -= 1
    runcard(p)
    --note: card was already set to 'discarded' (crd.status=1) back
    -- when cards were chosen from hand
    if (p.crd.burn) crd.status=2  --burn card instead
    del(p.crds,crd) --delete from list of cards shown in UI
  end
end

--execute the card that has been parsed into a.crd
-- (where a is a reference to an entry in actor[])
-- (called by _updactplayer() or _updactenemy()
function runcard(a)
  local crd=a.crd
  if crd.act=="😐" then  --a move action
    if a==p then
      changestate("actplayermove",0)
    else
      enemymoveastar(a)
    end
  elseif crd.aoe==8 and crd.rng==1 then
    --specific player AoE attack 'all adjacent' where no UI
    -- interaction to select targets is needed
    --TODO? generalize for multiple different AoE attacks (aoepat[#]?)
    --      but AoE attacks w/ selectable targets/directions would need to
    --      happen in an interactive attack mode like "actplayerattack"
    --TODO: save tokens here by reusing actplayerattack state in some way,
    --      similar code in both
    --list of the 8 (x,y) offsets relative to player hit by this 
    -- 'all surrounding enemeies' AoE, hard-coded as string for minimal tokens
    local targets=splt3d("x;-1;y;-1|x;0;y;-1|x;1;y;-1|x;-1;y;0|x;1;y;0|x;-1;y;1|x;0;y;1|x;1;y;1",true)
    aoe_xy_center=p --global used by addxydelta(), workaround for foreach() not taking multiple arguments
    foreach(targets,addxydelta) --modifies aoepat in place
    foreach(targets,pattackxy) --run attack for each AoE square
    changestate("actplayer",0)
  elseif crd.act=="█" then  --standard attack
    if a==p then
      changestate("actplayerattack",0)  --UI for target selection
    else
      enemyattack(a)  --run enemy attack for actor a
    end
  else  --other simpler actions without UI/selection
    --Note: currently each action is assumed to only do one thing,
    --      e.g. move, attack, heal, or so on.
    --TODO? implement code to allow player heal/shield actions 
    --      attached to a move/attack? (not needed for now)
    if (crd.act=="♥") healactor(a,crd.val)
    if crd.act=="★" then
      a.shld+=crd.val
      addmsg(a.name.." ★+"..crd.val)
    elseif crd.act=="⬅️" and a==p then
      addmsg("lOOTING tREASURE @➡️"..crd.val)
      rangeloot(crd.val)
    elseif crd.act=="smite" then  --god-mode attack (for testing, not actual game)
      foreach(inrngxy(p,crd.rng),pattackxy)
    elseif crd.act=="howl" then --special enemy attack
      addmsg(a.name.." hOWLS.. \f8-1♥,▥")
      dmgactor(p,1)
      p.stun=true
    elseif crd.act=="call" then
      summon(a)
    end
    if (a==p) changestate("actplayer",0)
  end
  if (crd.burn) p_xp+=2 --using burned cards adds xp
end

--run with foreach() to transform an aoe list of {x,y} deltas 
-- relative to a target into absolute positions
--requires global xydelta.x and .y are set before calling-- ugly!
-- (but since used with foreach() we can only have one argument)
--TODO:prototype alternate methods
--lint:aoe_xy_center
function addxydelta(xy)
  xy.x+=aoe_xy_center.x
  xy.y+=aoe_xy_center.y
end

--have player attack a square (occupied or not)
--can be called directly for single attack or passed to foreach() for multi attacks
function pattackxy(xy)
  local ai=actorat(xy.x,xy.y)
  if ai>1 then
    runattack(p,actor[ai])
  else
    --no enemy in target square, queue empty attack animation
    queueanim(nil,xy.x,xy.y,p.x,p.y,6)  
  end
end

--return all {x=x,y=y} cells within range r of actor a
-- (and on map, within LOS, not fogged, etc)
function inrngxy(a,r)
  local inrng={}
  for i=-r,r do
    for j=-r,r do
      local tx,ty=a.x+i,a.y+j
      local txy=xylst(tx,ty)
      if (not isfogoroffboard(tx,ty) and dst(a,txy)<=r and lineofsight(a,txy)) add(inrng,txy)
    end
  end
  return inrng
end

function longrest()
  p.actionsleft=0
  addmsg("yOU TAKE A \f7lONG rEST\f6:")
  --refresh discarded and items
  foreach(pdeck,refresh)
  foreach(pitems,refresh)
  healactor(p,3)
  --note: burning of the card selected along with 'rest' was done
  -- earlier in pdeckbld(), so that p.crds doesn't show that card before p's turn)
  -- now display the burn message configured back in pdeckbld()
  addmsg(restburnmsg)
end

--loot treasure (for player) at x,y
--TODO? can we simplify this code?
function loot(x,y)
  local m=mget(x,y)
  --flag 5 = if there's some 'lootable' object in the space
  if fget(m,5) then
    --set map to blank space
    mset(x,y,33)
    --1 to 3 stacked coin(s)
    if m>=13 and m<=15 then 
      getgold(gppercoin * (m-12))
    --herbs-to-collect, special level goal
    elseif m==12 then 
      herbs+=1
      addmsg("\f7yOU COLLECT SOME HERBS")
    --chest, random treasure depending on difficulty level
    elseif m==37 then
      local tv=5+rnd(5*difficulty)\1 --gold = 5-9, 5-14, 5-19, or 5-24, depending on level
      addmsg("yOU OPEN A CHEST...")
      getgold(tv)
    end
  end
end

function getgold(g)
  p_gp+=g
  camp_gold+=g
  addmsg("yOU GET "..g.."●")
end

--loot all treasures within rng r of player (no enemies currently loot)
--note: inrngxy() checks unfogged, in LOS, etc so you won't
--      loot through walls
function rangeloot(r)
  for xy in all(inrngxy(p,r)) do
    loot(xy.x,xy.y)
  end
end

---- state actplayermove (interactive player move action)
function initactplayermove()
  showmapsel=true --show selection box on map
  selx,sely=p.x,p.y
  mvq={xylst(selx,sely)}  --initialize move queue with current player location
  --TODO? find 12 tokens to add back in the '(jump)' message,
  --      removed to fill other last-minute token needs
  --local msg="move up to "..p.crd.val
  --if (p.crd.jmp) msg..=" (jump)"
  --addmsg(msg)
  --addmsg("move up to "..p.crd.val)
  setprompt("\fcさし🅾️\f6:mOVE "..p.crd.val.."     (\fc❎\f6:uNDO)")
  _updstate=_updactplayermove
  _drwstate=_drawmain   --could comment out to save 3 tokens since hasn't changed since last state (but that's risky/brittle to future state flow changes)
end

--player interactively builds step-by-step move queue
-- (not only destination: path matters due to traps or other triggers)
function _updactplayermove()
  local selx0,sely0=selx,sely
  selxy_update_clamped(10,10,0,0)
  --if player moved the cursor, try to move:
  if selx!=selx0 or sely!=sely0 then
    --NOTE: the commented out lines tried to streamline this code,
    --      but can't compare equality on two lists easily?
    --local selxy=xylst(selx,sely)
    --if #mvq>=2 and mvq[#mvq-1]==selxy then
    if #mvq>=2 and mvq[#mvq-1].x==selx and mvq[#mvq-1].y==sely then
      --if player moved back to previous location, trim move queue
      deli(mvq,#mvq)
    elseif #mvq>p.crd.val or not validmove(selx,sely,false,p.crd.jmp,1) then
      --if move not valid (would enter a tile with an obstacle/actor,
      -- unless we are jumping, or beyond player move range), cancel
      selx,sely=selx0,sely0
    else
      --valid move step, add to move queue
      --note: still might not be valid location to _end_ a move on,
      --      e.g. an obstacle tile while jumping, 
      --      but that's checked again when 🅾️ is pressed
      add(mvq,xylst(selx,sely)) --or pass in selxy if set above (not currently implemented)
    end
  end
  -- it's only valid to _end_ move here if it's a passable hex within range
  -- (global selvalid also affects how selection cursor is drawn, dashed or solid)
  selvalid = (#mvq-1) <= p.crd.val and validmove(selx,sely,true,false,1)
  if btnp(🅾️) then
    if selvalid then
      if (#mvq>1) sfx(0)
      --kick off move and animation
      --NOTE: animmovestep will also update p.x,p.y to move along the
      --      move queue as a side effect, not intuitive
      changestate("animmovestep",0)
    else
      addmsg("iNVALID mOVE")
    end
  elseif btnp(❎) then
    undoactplayer()
  end
end

--try to restore state and undo card selection
-- (for move and attack actions not completed)
--note: added late in development, tight on tokens
function undoactplayer()
  p.actionsleft+=1
  mvq={}
  crdplayed.status=1  --burned -> discarded (if it was a burn card we started to play)
  add(p.crds,crdplayed,crdplayedpos)
  changestate("actplayer")
end

--TODO? modify p.x,p.y separately vs as a side effect of this
--lint:apushed,pushdmg,apushedinto,pushblockx,pushblocky
function initanimmovestep()
  --if globel "apushed" is set, move that actor, 
  --  otherwise move global actor # actorn
  local a=apushed or actor[actorn]
  if not mvq or #mvq<=1 then
    --we're done with animation, run next player/enemy action
    mvq={}
    --if this move was a blocked push, apply push dmg set in runattack()
    if apushed and pushdmg then
      -- check in case pushed enemy already died mid-push (via a trap)
      if apushed.hp>0 then
        addmsg(" cOLLISION dAMAGE:\f8-"..pushdmg.."♥")
        dmgactor(apushed,pushdmg)
        --if pushed first actor into a 2nd actor, also damage them
        if (apushedinto) dmgactor(apushedinto,pushdmg)
        --add pushdmg animation
        --TODO? add unique sprite/animation to better indicate push?
        -- blue box to frame dmg animation (commented out to save tokens)
        --queueanim(nil,pushblockx,pushblocky,apushed.x,apushed.y,157)
        -- reusing attack dmg animation (saves tokens, shows collision dmg)
        queueanim(nil,pushblockx,pushblocky,apushed.x,apushed.y,144+pushdmg)
      end
      pushdmg=false
    end
    apushed=nil --reset global "actor being pushed"
    if actorn==1 then
      changestate("actplayer",0)
    else
      changestate("actenemy",0)
    end
  else
    --queue up a one-step animation (will do this multiple times
    -- until each step in mvq has been animnated and taken)
    local x0,y0=mvq[1].x,mvq[1].y
    local xf,yf=mvq[2].x,mvq[2].y
    --deli(mvq,1) --done in updanimmovestep() instead
    queueanim(a,xf,yf,x0,y0)
    _updstate=_updanimmovestep
    --check for any immediate triggers
    -- for space moved into (trap, door)
    --the "a.crd and" ensures that if no a.crd exists
    -- (only case so far: enemy being pushed before it's
    --  had its move?) we don't error out reading a.crd.jmp
    checktriggers(a,a.crd and a.crd.jmp)
  end
end

--check for any triggers on location actor a is on
-- (intended to be run both during move and at end of move)
--jmp = "is actor jumping?"" (don't pass it for end of move check)
--NOTE: flag 5 (treasure) is not checked here, because it's currently
--      handled by an end-of-turn call to loot() to loot only the square
--      player ends turn on (could consider different gameplay in future)
function checktriggers(a,jmp)
  local ax,ay=a.x,a.y
  local m=mget(ax,ay)
  --sprite with trigger
  if fget(m,4) then
    --stepped on trap
    if m==43 and not jmp then
      addmsg(a.name.." @ tRAP! \f8-"..trapdmg.."♥")
      --clear hex before damaging actor, so that if enemy
      -- is killed by trap, it drops coin where trap was
      mset(ax,ay,33)
      dmgactor(a,trapdmg)
    --if on door, open next room
    elseif fget(m,7) then
      for i=1,4 do
        unfogroom(ax+dirx[i],ay+diry[i])
      end
      --init any new enemies revealed
      initactorxys()
      doorsleft-=1
      mset(ax,ay,33)
    --brazier player can light herbs on, special level goal
    elseif m==24 and a==p then
      herbs+=1
      --change map to "burning herbs" sprite
      mset(ax,ay,28)
      addmsg("\f7yOU LIGHT A BUNDLE OF\n\f7  HERBS, SMOKE RISES..")
    end
  end
end

--NOTE: program flow is not the most intuitive here.
--the global state is set to animmovestep in tandem with an animation
--      being kicked off (animt=0), so this upd() function will not
--      actually be called during the animation, until the animation is done
--      and updstate() is called. so this is run once at the end of each animated
--      single-map-tile step, to trim the movequeue and then rerun initanimmovestep()
function _updanimmovestep()
  deli(mvq,1)
  --changing state to self, as a way to rerun initanimmovestep() and take the next step
  changestate("animmovestep",0)
end

---- actplayerattack state (attack target selection UI)

function initactplayerattack()
  showmapsel=true
  selx,sely=p.x,p.y
  setprompt("\fcさし🅾️\f6:aTK tARGET (\fc❎\f6uNDO)")
  _updstate=_updactplayerattack
  _drwstate=_drawmain   --could comment out to save 3 tokens since hasn't changed since last state (but that's risky/brittle to future state flow changes)
end

function _updactplayerattack()
  selxy_update_clamped(10,10,0,0)
  --variables set based on current target cursor
  local xy=xylst(selx,sely)
  local d=dst(p,xy)
  local crd=p.crd
  --selection is valid target if (and only if) following conditions are true:
  -- (in range, not self, not fogged, has LOS if ranged)
  -- this global then affects how selection cursor is drawn and whether action can be selected below
  selvalid = d <= crd.rng and d>0 and not isfogoroffboard(selx,sely) and lineofsight(p,xy)
  --drawaoesel = crd.aoe
  if btnp(🅾️) then
    if selvalid then
      --drawaoesel=false
      --TODO?: make this line more token-efficient w/ splt3d (but splt3d("x;0;y;0",true) doesn't work)
      local targets={{x=0,y=0}} --default targets is just selected one
      --otherwise, for AoE attack (in particular, ranged AoE attack, since
      -- melee AoE attack is special-case handled elsewhere)
      if (crd.aoe) targets=splt3d("x;-1;y;-1|x;0;y;-1|x;1;y;-1|x;-1;y;0|x;0;y;0|x;1;y;0|x;-1;y;1|x;0;y;1|x;1;y;1",true)
      --for normal attacks, below just adds the xy.x,xy.y of the
      -- to a 0,0 placeholder, same as pattackxy(xy)
      --but this format enables AoE ranged attacks as an alt version
      aoe_xy_center=xy --global, used by addxydelta() below
      foreach(targets,addxydelta)
      foreach(targets,pattackxy)
      --special case: if enemy is in middle of being pushed as a result
      -- of attack, don't move to the actplayer state to select the next
      -- card until that's done... (pushing execution will itself change
      -- to actplayer when done)
      if not apushed then 
        changestate("actplayer",0)
      end
    else
      addmsg(" iNVALID tARGET")
    end
  elseif btnp(❎) then
    undoactplayer()
  end
end

-----
----- 5) post-combat turn states
-----

---- state: cleanup (aka end of turn)

function initcleanup()
  for a in all(actor) do
    -- clean up actor hands
    clearcards(a)
    --TODO: remove this if cards are not stored at the "type" level?
    --      (currently enemies store cards redundantly in actor and actor.type)
    if (a.type) clearcards(a.type)
    --process wound condition
    if a.wound and a.hp>0 then
      addmsg(a.name.." wOUNDED ∧:\f8-1♥")
      dmgactor(a,1)
    end
    --remove certain one-turn buffs
    a.shld=a.pshld
    --check space triggers (e.g. end move on trap, door)
    --note: trap, door already checked during move actions, so
    --      this may be redundant and not catch any new triggers?
    checktriggers(a)
    --cleanup dead enemies (except player)
    if (a.hp<=0 and a!=p) del(actor,a)
  end
  --check if ended turn on treasure
  loot(p.x,p.y)  
  --check if all enemies defeated or a special win con is met
  -- (all items collected, boss killed on last level, etc)
  if (#actor==1 and doorsleft==0) or ((dlvl==14 or dlvl==16) and herbs==4) or (dlvl==22 and not indextable(actor,"noah","name")) then
    winlevel()
  elseif checkexhaust() then
    --check if player out of hp or cards
    loselevel()
  else
    --if hand doesn't have 2+ cards left, must short rest
    --  note: checked in checkexhaust() above to ensure discard
    --        pile had enough cards to short rest
    if #cardsleft()<2 then
      local burned=shortrestdeck()
      addmsg("\fchAND EMPTY\f6: yOU sHORT\nrEST, REDRAW, AND \f8bURN\nRANDOM CARD: \f8[\f6"..burned.."\f8]")
    end
    setprompt("\fcし\f6:rEVIEW \fc🅾️\f6:nEXT rOUND")
    --entering "scroll message log", effectively a new state, but
    -- didn't seem worth state machine overhead to create
    -- an actual state, so indicating it with global msgreview
    msgreview,nextstate,_updstate=true,"newturn",_updscrollmsg
    _drwstate=_drawmain   --could comment out to save 3 tokens since hasn't changed since last state (but that's risky/brittle to future state flow changes)
  end
end

function shortrestdeck()
  --refresh discarded
  foreach(pdeck,refresh)
  --burn random card in hand (since all discards back in hand)
  local crd=rnd(cardsleft())
  crd.status=2
  --return card burned, to allow message about it
  return crd.act
end

--return list of cards in hand (not discarded or burned)
-- (if incldiscards==true, also include non-burned discards)
--note: returns the list of cards not the number of cards,
--      so often called as #cardsleft()<##
function cardsleft(incldiscrds)
  local crds={}
  for crd in all(pdeck) do
    if (crd.status==0 or (incldiscrds and crd.status==1)) add(crds,crd)
  end
  return crds
end

---- state: scrollmsg (review message queue)
--lint: msgpause
function _updscrollmsg()
  if btnp(🅾️) then
    --TODO: save token by skipping 2nd assignment? (default=nil)
    msgreview,msgpause=false,false
    changestate(nextstate)
  elseif btn(⬆️) then
    --stop auto-scroll mode once player hits up arrow
    msgpause=true
    msg_yd=max(msg_yd-1,0)
  elseif btn(⬇️) and #msgq>3 then
    msg_yd=min(msg_yd+1,(#msgq-3)*6)
  end
end

---- state: end level

function initendlevel()
  decksreset()
  setprompt("\fcし\f6:rEVIEW 🅾️:eND sCENARIO")
  msgreview=true
  --record time elapsed in level, in 6sec multiples, for campaign stats
  -- (2^15 * 6sec ~ 50 hour rollover of variable)
  --TODO: handle timer rollover or check for negative values
  --      maybe a clever use of %mod can extract even if rolled over
  --      (for now, abs() as token-efficient way to at least not
  --       accumulate negative values if a level is left open and
  --       unattended 9+ hours and timer rolls over, though values would then be wrong)
  camp_time+=abs(time()-levelstarttime)\6
  --wait for player to continue before displaying post-level
  -- text (since that will overwrite view of map)
  nextstate,_updstate="pretown",_updscrollmsg
end

--still end of level, draw post-level text
function initpretown()
  setprompt("\fc🅾️\f6:rETURN TO tOWN")
  nextstate,_drwstate="town",_drawlvltxt
  --could comment below out to save 3 tokens since we know _updstate was already set
  -- to this in initendlevel() last state (but that's risky/brittle to future state flow changes)
  _updstate=_upd🅾️
end

--end of level helpers

--lint: lastlevelwon
function winlevel()
  local l=lvls[dlvl]
  p_xp+=l.xp
  addmsg("\f7victory!  \f6(+"..l.xp.."xp)")
--  commented out gold msg to save tokens
--  TODO? restore this (but... redundant with getgold() msg)
--  p_gp+=l.gp
--  if (l.gp>0) addmsg(" you are paid ●"..l.gp)
  if (l.gp>0) getgold(l.gp)
  mapmsg=fintxt[dlvl]
  lastlevelwon=dlvl
  --lock level to avoid replay
  l.unlocked=0
  --unlock new levels
  for u in all(split(l.unlocks)) do
    if (u!="") lvls[tonum(u)].unlocked=1
  end
  if dlvl==22 then
    wongame=1
    --increment all-time campaign wins in savegame, persisting across multiple "start new game" campaigns
    -- (not yet displayed to user, or used for anything, but had some ideas...)
    camp_wins+=1  
  end
  --NOTE: tried a different approach to below in the past (didn't seem necessary, and a few more tokens): 
  --      instead of changestate() here, set a global leveldone=true
  --      and initcleanup() checked that global and did the changestate()
  changestate("endlevel",0)
end

function checkexhaust()
  if (p.hp<=0) return true
  --if < 2 cards in deck (including discards)
  if (#cardsleft(true)<2) return true
  --if 2 cards in deck but < 2 cards in hand (so a short/long rest would fail)
  if (#cardsleft(true)==2 and #cardsleft()<2) return true
  --return false  --redundant since default return is nil which evals to false?
end

function loselevel()
  addmsg("\f8yOU ARE eXHAUSTED")
  mapmsg="dEFEATED, YOU HOBBLE BACK TO TOWN TO NURSE YOUR WOUNDS AND PLAN A RETURN."
  changestate("endlevel",0)
end

-----
----- 6) main UI draw loops and support functions
-----

--like cls(c) but respects clip(), for wipes/fades
function clsrect(c)
  rectfill(0,0,127,127,c)
end

-- main draw UX (map, msgs, enemy+player HUD (heads-up displays))
function _drawmain()
  clsrect(0)
  drawstatus()
  drawmapframe()
--  addstat1() --for cpu usage debugging
  drawmap()
--  addstat1()
  drawheadsup()
--  addstat1()
  -- draw msgs last, since they set a clip()
  drawmsgbox()
end

function drawstatus()
  print(sub(lvls[dlvl].name,1,15),0,0,7)
  printmspr("♥"..p.hp.."/"..p.maxhp,66,0,8)
end

--lint:prompt
function drawmsgbox()
  local c=msgreview and 12 or 13
  rectborder(msg_x0,99,msg_x0+msg_w-1,120,5,c)
  --clip based on overlap of screenwipe and msgbox
  clip(max(msg_x0,wipe)+1,
      max(101,wipe),
      min(msg_x0+msg_w,127-2*wipe)-max(msg_x0,wipe)-2,
      120-2*wipe-max(101,wipe))
--- DEBUG: visualize clipping rectangle (may be obsolete)
--  rect(max(msg_x0,wipe)+1,
--           max(101,wipe),
--           max(msg_x0,wipe)+1-1 + min(msg_x0+msg_w,127-2*wipe)-max(msg_x0,wipe)-2,
--           max(101,wipe)-1 + 120-2*wipe-max(101,wipe),14)
  --draw messages (a long list that will run off screen, typically,
  --  but clipped to only update within message box area)
  textboxm(msgq,msg_x0,98-msg_yd,msg_w,23,2,5)
  clip()
  --UI for message scrolling
  if (msgreview) printmspr("\fc⬆️\n\n\n\|f⬇️",89,99)
  --also draw a single "prompt string" below msgbox
  drawprompt()
end

function drawprompt()
  if (prompt) printmspr(prompt,1,122)
end 

function setprompt(str)
  prompt=str
end

function drawmapframe()
  rectborder(0,6,91,97,0,5)
end

--main play area map drawing
function drawmap()
  --screenshake map in some cases (e.g. draw "2x" mod)
  camera(rnd(shake),rnd(shake))
  --draw sprites (not using map(), to handle animated tiles, fog, etc)
  for i=0,10 do
    for j=0,10 do
      local sprn=mget(i,j)
      --animated environment
      if (fget(mget(i,j),3)) sprn+=afram
      if (isfogoroffboard(i,j)) sprn=39
      --NOTE: 2,8=map_x0+2,y0+2
      spr(sprn,2+8*i,8+8*j)
    end
  end
  camera(0,0)
  --draw actors (player + enemies + ephemeral animations)
  --note: despite looping through actor[] in order,
  --      drawactor includes a hack to always draw player on top of enemies (e.g. if jumping)
  --      (if we did that at this level, player would draw on top of attack animations, which we don't want)
  foreach(actor,drawactor)

  --draw path along move queue if one exists
  --note: initially only existed for debugging but I liked the look,
  --      so left it in (could remove if tokens needed) 
  if #mvq>1 then
    local x0,y0=mvq[1].x,mvq[1].y
    for mv in all(mvq) do
        line(6+8*x0,12+8*y0,6+8*mv.x,12+8*mv.y,12)
        x0,y0=mv.x,mv.y
    end
    circfill(6+8*x0,12+8*y0,1,12)
  end
  if (showmapsel) drawmapsel()
end

function drawactor(a)
  local animfram = a.noanim and 0 or afram
  --show stunned actors as blue and frozen (~19tok)
  if a.stun then
    animfram=0
    --TODO: is there a more token-efficient way to bulk-set palette?
    pal(splt("1;12;3;12;4;12;5;12;6;12;7;12;13;12",false,true))
  end
  spr(a.spr+animfram,2+8*a.x+a.ox,8+8*a.y+a.oy)
  pal()
  palt(0b0000000000000010)
  --TODO? in future also check if a pushed actor is active and draw
  --      that on top (not relevant for now as pushes don't pass through other actors)
  --local amoving=apushed or actor[actorn]
  local amoving=actor[actorn]
  --a!=amoving check needed to avoid infinite call loop of drawactor(amoving)
  if (amoving and a!=amoving and not a.ephem) drawactor(amoving)
end

function drawmapsel()
  --prototype of large 3x3 map square selection cursor for AoE attacks
  -- (decided it wasn't worth the tokens, never finished)
  --local s=drawaoesel and 25 or 9
  --local mx,my=5+selx*8-s\2,11+sely*8-s\2
  local mx,my=1+selx*8,7+sely*8
  if (not selvalid) fillp(0x5a5a)  --dashed border
  rect(mx,my,mx+9,my+9,12)
  --rect(mx,my,mx+s,my+s,12)
  fillp()
  --line(6+p.x*8,12+p.y*8,5+mx,5+my,8) --LOS debugging line
end

-- draw: enemy cards --

--draw enemy cards for actor #n
--typically, base with just maxhp, and then any action cards covering it
--if enemy is "selected" (for inspection by player)
-- instead show HP, conditions like stun/wound, etc
function drawecards(x,y,n,sel)
  local a=actor[n]
  if (not sel) drawcardbase(x,y,a,sel)
  --show ability card
  --using a.type.crds instead of a.crds, in case a new enemy instance 
  -- was revealed (e.g. by opening a door), it will have no a.crds since
  -- it didn't exist at beginning of combat, but if it has allies
  -- of the same type, a.type.crds will contain their cards
  local acrds=a.type.crds
  if acrds and #acrds>=1 then
    local strs={}
    for crd in all(acrds) do
      add(strs,crd.act)
    end
    --draw enemy's action cards
    textboxm(strs,x+10,y+10,25,15,nil,nil,1)
    --linking to a.type. instead of a. in case new instance of an enemy revealed (woudn't have initiative yet)
    printmspr(a.type.init.."\-f:",x+2,y+15,7)
  end
  --if enemy is selected for inspection, draw base on top of action cards instead
  if (sel) drawcardbase(x,y,a,sel)
end

--draw actor a's base card (player or enemy)
-- base card is frame, sprite, name, hp, conditions
function drawcardbase(x,y,a,sel)
  local str={"   "..a.name}
  --TODO? add enemy level in future if we have enemy levels
  local c,h = 13,22 --color, box height
  local hpstr = "?/"..a.maxhp
  --build 'actor status' string
  local st="\n\|b \-e"
  if (a.wound) st..="∧ \-f"
  if (a.stun) st..="▥ \-f"
  if (a.shld>0) st..="★"..a.shld
  --special player vs. enemy tweaks to display details
  if a==p then
    h = 37
    if (p.init) add(str,"\n\|d \-e\f7"..p.init..":")
    add(str,"\n"..st)
    --add item icons
    --UI bug: if >4 or 5 icons, will run off screen,
    --        add code to wrap to next line? 
    --note: commented item icon printing out entirely to save tokens
    --      for other uses, and sidestep that visual glitch
--    if #pitems>0 then
--      --add(str,"\n\n\|citems:")
--      st="\n\n\|d \-e"
--      for it in all(pitems) do
----        --commented out to save tokens
----        --'dark' icon for used items
----        st..=it.status==0 and it[5] or it[6] 
--        st..=it.icon
--      end
--      add(str,st)
--    end
  else --enemy-specific display
    if sel then
      --TODO? combine assignments into one line to save 2 tokens
      hpstr=a.hp
      c=12
    end
    add(str,"   ♥"..hpstr)
    if (sel) add(str,st)
  end
  textboxm(str,x,y,33,h,nil,c)
  spr(a.spr,x+2,y+2)
end

--draw player cards (and base)
function drawpcards()
  local hx,hy=hud_x0+2,hud_py+7
  drawcardbase(hud_x0,hud_py,p)
  --in most combat-related states except when player is actively
  -- choosing a card to play, show the two cards player chose
  -- from hand (or one if it's "rest")
  --TODO? find alternate to checking global actorn
  if state=="precombat" or state=="actenemy" or state=="actloop" or state=="animmovestep" and actorn!=1 then
    if p.crds then
      for i=1,min(#p.crds,2) do
        drawcard(p.crds[i],hx,hy+10*i)
      end
    end
  elseif sub(state,1,9)=="actplayer" or state=="animmovestep" and actorn==1 then
    --but if during player turn, show all player options
    -- (up to 4 including the default move/attack options)
    for i,crd in ipairs(p.crds) do
      --shade default mv/atk cards (which have undefined initiative)
      local style=0
      if (not crd.init) style=5
      local cardsel=(i==sely and state=="actplayer")
      drawcard(crd,hx,hy-10+10*i,style,cardsel)
      --TODO: check if this is unnecessary and we could save a few tokens, 
      --      since drawcard->textboxm() already resets fillp() if used?
      fillp()
    end
  end
end

--draw a card with various styles and options
function drawcard(card,x,y,style,sel,lg,rawtext)
  -- by default, draws small one-line version,
  --   but if lg==true, draws large card on right

  --style sets frame/texture:
  --  nil/0: default box
  --  1: faded (discarded, used)
  --  2: burned
  --  3: no border
  --  4: multi-item selection
  --  9: read style from card.status

  -- sel: is card selected? (draws outer border)

  --if rawtext, assume card is a string or list of strings
  --  rather than a card data structure
  --  (and this acts mostly a wrapper for textboxm())
  local strs=card
  if not rawtext then
    if lg then
      strs=desccard(card)
    else
      --TODO? add back in microspacing
      --TODO? only display first 7 chars (for items in profile)
      if (type(card)=="table") strs=card.act
    end
  end
  local c1,c2,c3,cf,c4=13,1,6 --default colors
  local w,h,b=32,9,1  
  if (style==9) style=card.status
  if lg then
    w,h,b=39,67,3
  else
    --TODO? can we save tokens by reading from array structure, e.g.
    -- styledata=splt3d("0;1;5;1|0;0x82;0;1....")
    -- c1=styledata[style][1]
    if (style==1) c1,c3,cf=0,5,true
    if (style==2) c1,c2,c3,cf=0,0x82,0,true
    if (style==3) c1=5
    if (style==4) c1=12
    if (style==5) c2=0
    if (sel) c4=12
  end

  textboxm(strs,x,y,w,h,b,c1,c2,c3,cf,c4)

  if (lg and not rawtext) then
    --divider line on card
    line(x,y+18,x+w-1,y+18,c1)
    --print initiative in circle
    circfill(x+w-2,y-1,7,c2)
    circ(x+w-2,y-1,7,c1)
    print(card.init,x+w-5,y-3,c3)
  end
end

--return a list of formatted strings descibing a card
-- based on its actions/values/modifiers
-- (for the lg card preview box in drawcard())
function desccard(card)
  local crd=parsecard(card.act)
  local strs={"\f7"..card.name,"",""}
  --NOTE: special cards ("smite", etc) have decsriptions in their
  --      card.name data in the database, rather than being generated here
  if not crd.special then
    addflat(strs,descact[crd.act]..crd.val)
    --TODO? save tokens by doing some lookup into descact[] for the
    --      3rd/4th/5th characters in card string rather than writing
    --      the below code for each property?
    if (crd.jmp) add(strs," jump")
    if (crd.rng>1) add(strs," @ rng "..crd.rng)
    if (crd.wound) add(strs," \f8wound")
    if (crd.stun) add(strs," \fcstun")
    if (crd.push) add(strs," \fcpush\f6 "..crd.push.."\n\n+1█ per\nそ pushed\nif into\nobstacle")
    if (crd.aoe) addflat(strs,"multiple\n targets")
    if (crd.burn) add(strs,"\n\f8burn\f6 crd\n on use")
  end
  return strs
end

--overall hud (right panel with enemy+player info and cards)
function drawheadsup()
  --draw enemy cards
  -- assign enemy types to HUD slots
  -- ehudn can hold up to three enemy types, as name strings
  -- (in a few levels, four enemy types may exist occasionally, with summons
  --  and objectives-- they'll be overdrawn by the player hud unfortunately)
  local ehudn={}
  for i,a in ipairs(actor) do
    if a!=p and not a.ephem then
      local enam=a.name
      --add name of an enemy type to ehudn if there
      -- isn't already a row for it, and draw its action card
      -- (only does this once per enemy type)
      if not indextable(ehudn,enam) then
        add(ehudn,enam)
        drawecards(hud_x0,hud_ey*indextable(ehudn,enam)-hud_ey,i)
      end
    end
  end
  --if an enemy (actor# > 1) is highlighted with the cursor, 
  -- draw its current-hp-stats card on top of 
  -- the standard enemy type actions card drawn above
  local n=actorat(selx,sely)
  if n>1 and showmapsel then
    drawecards(hud_x0,hud_ey*indextable(ehudn,actor[n].name)-hud_ey,n,true)
  end
  --draw player cards
  drawpcards()
end

-----
----- 7) custom sprite-based font and print functions
-----

--uses pico8 0.2.2+ features to embed dungeon sprites as characters in custom font
-- fonts and poke() string created in helper cart "phfontgen.p8"
--TODO(future): consider 0.2.5 variable font width as well
--lint: func::_init
function initfont()
  --custom font: lower case, sprite icon replacements
  poke(0x5600,unpack(split"4,6,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,7,7,7,7,7,0,0,0,0,7,7,7,0,0,0,0,0,7,5,7,0,0,0,0,0,5,2,5,0,0,0,0,0,5,0,5,0,0,0,0,0,5,5,5,0,0,0,0,4,6,7,6,4,0,0,0,1,3,7,3,1,0,0,0,7,1,1,1,0,0,0,0,0,4,4,4,7,0,0,0,5,7,2,7,2,0,0,0,0,0,2,0,0,0,0,0,0,0,0,1,2,0,0,0,0,0,0,3,3,0,0,0,5,5,0,0,0,0,0,0,2,5,2,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,0,2,0,0,0,5,5,0,0,0,0,0,0,5,7,5,7,5,0,0,0,7,3,6,7,2,0,0,0,5,4,2,1,5,0,0,0,3,3,6,5,7,0,0,0,4,2,0,0,0,0,0,0,2,1,1,1,2,0,0,0,2,4,4,4,2,0,0,0,5,2,7,2,5,0,0,0,0,2,7,2,0,0,0,0,0,0,0,2,1,0,0,0,0,0,7,0,0,0,0,0,0,0,0,0,2,0,0,0,4,2,2,2,1,0,0,0,7,5,5,5,7,0,0,0,3,2,2,2,7,0,0,0,7,4,7,1,7,0,0,0,7,4,6,4,7,0,0,0,5,5,7,4,4,0,0,0,7,1,7,4,7,0,0,0,1,1,7,5,7,0,0,0,7,4,4,4,4,0,0,0,7,5,7,5,7,0,0,0,7,5,7,4,4,0,0,0,0,2,0,2,0,0,0,0,0,2,0,2,1,0,0,0,4,2,1,2,4,0,0,0,0,7,0,7,0,0,0,0,1,2,4,2,1,0,0,0,7,4,6,0,2,0,0,0,2,5,5,1,6,0,0,0,0,6,5,5,6,0,0,0,1,1,3,5,3,0,0,0,0,6,1,1,6,0,0,0,4,4,6,5,6,0,0,0,0,6,3,1,6,0,0,0,4,2,7,2,2,0,0,0,0,6,5,7,4,3,0,0,1,1,3,5,5,0,0,0,2,0,2,2,2,0,0,0,2,0,2,2,3,0,0,0,1,1,5,3,5,0,0,0,2,2,2,2,4,0,0,0,0,7,7,5,5,0,0,0,0,3,5,5,5,0,0,0,0,2,5,5,2,0,0,0,0,3,5,3,1,1,0,0,0,6,5,6,4,4,0,0,0,6,1,1,1,0,0,0,0,6,3,4,3,0,0,0,0,2,7,2,4,0,0,0,0,5,5,5,6,0,0,0,0,5,5,7,2,0,0,0,0,5,5,7,7,0,0,0,0,5,2,2,5,0,0,0,0,5,5,7,4,3,0,0,0,7,2,1,7,0,0,0,3,1,1,1,3,0,0,0,1,2,2,2,4,0,0,0,6,4,4,4,6,0,0,0,2,5,0,0,0,0,0,0,0,0,0,0,7,0,0,0,2,4,0,0,0,0,0,0,6,5,7,5,5,0,0,0,7,5,3,5,7,0,0,0,6,1,1,1,6,0,0,0,3,5,5,5,3,0,0,0,7,1,3,1,7,0,0,0,7,1,3,1,1,0,0,0,6,1,1,5,7,0,0,0,5,5,7,5,5,0,0,0,7,2,2,2,7,0,0,0,7,2,2,2,3,0,0,0,5,5,3,5,5,0,0,0,1,1,1,1,7,0,0,0,7,7,5,5,5,0,0,0,3,5,5,5,5,0,0,0,6,5,5,5,3,0,0,0,7,5,7,1,1,0,0,0,2,5,5,3,6,0,0,0,3,5,3,5,5,0,0,0,6,1,7,4,3,0,0,0,7,2,2,2,2,0,0,0,5,5,5,5,6,0,0,0,5,5,5,7,2,0,0,0,5,5,5,7,7,0,0,0,5,5,2,5,5,0,0,0,5,5,7,4,7,0,0,0,7,4,2,1,7,0,0,0,6,2,3,2,6,0,0,0,2,2,2,2,2,0,0,0,3,2,6,2,3,0,0,0,0,4,7,1,0,0,0,0,0,2,5,2,0,0,0,0,16,8,5,2,5,0,0,0,17,10,4,10,17,0,0,0,0,0,4,0,0,0,0,0,0,31,14,4,0,0,0,0,21,0,21,0,21,0,0,0,14,23,31,31,14,0,0,0,14,31,31,31,14,0,0,0,10,31,31,14,4,0,0,0,21,0,0,0,0,0,0,0,6,9,9,29,9,0,0,0,0,0,0,0,31,0,0,0,4,14,21,4,31,0,0,0,3,3,15,31,31,0,0,0,3,3,15,31,0,0,0,0,14,17,21,17,14,0,0,0,4,12,31,12,4,0,0,0,0,0,4,2,1,0,0,0,23,12,28,18,17,0,0,0,31,31,31,14,4,0,0,0,4,0,17,0,4,0,0,0,0,4,14,31,0,0,0,0,0,0,0,0,0,0,0,0,4,14,23,31,14,0,0,0,14,21,27,21,14,0,0,0,0,0,31,0,0,0,0,0,21,4,31,4,21,0,0,0,18,9,5,18,13,0,0,0,4,17,4,17,4,0,0,0,0,10,31,10,0,0,0,0,14,31,31,14,14,0,0,0,28,24,20,2,1,0,0,0,14,27,19,31,14,0,0,0,14,21,27,21,14,0,0,0,14,31,31,31,14,0,0,0,10,17,31,17,10,0,0,0,14,21,4,21,14,0,0,0,0,10,27,10,0,0,0,0,4,14,0,14,4,0,0,0,4,12,31,12,4,0,0,0,10,31,10,31,10,0,0,0,31,17,17,17,31,0,0,0,0,0,0,0,0,0,0,0,2,1,0,16,8,0,0,0,0,0,4,0,0,0,0,0,0,0,10,0,0,0,0,0,0,14,21,14,4,0,0,0,0,8,4,2,1,0,0,0"))
  poke(0x5f58,0x81) --always use font unless "\015oldfont\014" used
  fontsub=splt(" ; \-f;[;[\-f;];\-f];(;(\-f;);\-f);:;\-f:;█;\f6█;▒;\f8▒;🐱;_;⬇️;\fc⬇️;░;\f8░\-a\f6🐱;✽;_;●;\fa●\-a\f9✽;♥;\f8♥;☉;\f8☉\-a\f6🐱;웃;\f6웃;⌂;_;⬅️;\f6⬅️\-a\f9⌂;😐;\f6😐\-a\f4♪;♪;_;🅾️;\fc🅾️;◆;\fc◆\f6;…;_;➡️;\f6➡️\-a\f4…;★;\f6★;⧗;\f8⧗\-a\f6🐱;⬆️;\fc⬆️;∧;\f8∧;❎;\fc❎;▤;\f8▤;▥;\fc▥;あ;あ\-a\f8ち;い;い\-a\f8つ;う;う\-a\f1て;え;え\-a\fdと;お;\f8お\-a\f6な;く;\f8く\-a\f6き;け;\fcけ\f6;こ;\fcこ\f6;さ;\fcさ\f6;し;\fcし\f6",false,true)
  --test version w/ some diy proportional characters (WIP)
  --fontsub=splt("I;\-fI\-f;J;J\-f;L;\-fL; ; \-f;[;[\-f;];\-f];(;(\-f;);\-f);:;\-f:;█;\f6█;▒;\f8▒;🐱;_;⬇️;\fc⬇️;░;\f8░\-a\f6🐱;✽;_;●;\fa●\-a\f9✽;♥;\f8♥;☉;\f8☉\-a\f6🐱;웃;\f6웃;⌂;_;⬅️;\f6⬅️\-a\f9⌂;😐;\f6😐\-a\f4♪;♪;_;🅾️;\fc🅾️;◆;\fc◆\f6;…;_;➡️;\f6➡️\-a\f4…;★;\f6★;⧗;\f8⧗\-a\f6🐱;⬆️;\fc⬆️;∧;\f8∧;❎;\fc❎;▤;\f8▤;▥;\fc▥;あ;あ\-a\f8ち;い;い\-a\f8つ;う;う\-a\f1て;え;え\-a\fdと;お;\f8お\-a\f6な;く;\f8く\-a\f6き;け;\fcけ\f6;こ;\fcこ\f6;さ;\fcさ\f6;し;\fcし\f6",false,true)
end

--take input string to display, replaces CAPITAL chars representing
-- icons (sword, shield, etc) with their potentially two-color P8SCII
-- code (to print two characters overlapped)
--and then prints it...
--TODO(BUG): error if c>9 (need to convert # to hex value)
function printmspr(str,x,y,c)
 c = c or 6
 local newstr="\14" --"use custom font"
 for i=1,#str do
    local ch=str[i]
    --by default, if color is 6 (or if no color c param passed), default color is grey (6) and icons are multicolor
    -- but if color was manually set, don't run substitutions (muted simpler icons)
    --TODO: revert the 'and c==6'? this makes it less general, no longer handles pixel offsets, etc
    --      or add a (more tokens) more abstracted "each icon has primary and secondary colors"
    --TODO: remove special case ch==" " (and remove 'and c==6') and see where used?
    if ch==" " then
      ch=" \-f"  --hack to shorten spaces only
		elseif fontsub[ch] and c==6 then
--      ch=fontsub[ch].."\f"..c
      ch=fontsub[ch].."\f6"
    end
    newstr..=ch
 end
 print(newstr,x,y,c)
 --return newstr
end

-- simple print text wrapped to width<=w, break on spaces, more space for newlines
function printwrap(longtxt,w,x,y,c)
  local txts=split(longtxt,"\n")
  for txt in all(txts) do
    while #txt>w do
      local i=w+1
      while txt[i]!=" " do
        i-=1
      end
      print(sub(txt,1,i),x,y,c)
      txt=sub(txt,i+1)
      y+=6  --or could be 7 for more interline space...
    end
    print(sub(txt,1,w),x,y,c)
    y+=9  --slightly more space between paragraphs (for '\n' characters)
  end
end

-- accept either a list of strings or a single string
-- print it (including icons in custom font) with a given border
--
-- c1,c2,c3: colors (see in-code comments)
-- cf: 50% fill pattern in box?
-- c4: color of second outer box (e.g. selection cursor), omit if empty/nil/false
-- w,h: box width,height (if h is false/nil, auto-set from strings)
-- TODO? could save a few tokens with single-line assignments
--       if the minifier doesn't already do that
function textboxm(strs,x,y,w,h,b,c1,c2,c3,cf,c4)
  b=b or 1
  c1=c1 or 13 --border color
  c2=c2 or 5  --bkgnd color
  c3=c3 or 6  --txt color
  if (type(strs)!="table") strs={strs}
  h=h or #strs*6+3  --if height not set, set it by number of lines of strings
---  w=w or maxstrlen(strs)*4+3+3 --fit width to data?
  if (cf) fillp(0x5a5a)  --50% fill pattern
  rectborder(x,y,x+w-1,y+h-1,c2,c1)
  fillp()
  for i,str in ipairs(strs) do
    printmspr(str,x+b+1,y+b-5+6*i,c3)
  end
  --if not nil, draw extra outer border (show selection, etc)
  if (c4) rect(x-1,y-1,x+w,y+h,c4)
end

----
---- 8) menu-draw and related functions
----

--draw multiple columns of cards / items using drawcard(),
-- with 0 to many of them highlighted as selected
-- and (typically) the currently selected one previewed large on the right
--used in many different places (hand, upgrades, profile, etc)
--TODO? trim some tokens w/ multiple assignments per line?
--     if the minifier doesn't already do that
function drawcardsellists(clsts,x0,y0,sellst,style,spacing,modmode)
  --clsts = {list of lists of cards (one per column)}
  --sellst = list containing selected cards (for highlights)
  --style either sets style, or if ==9 it means "read style from card"
  --modmode = hacky: called from drawupgrademod() which needs diff behavior
  --note: can also be passed lists of strings not cards
  sellst = sellst or {}
  spacing = spacing or 36
  x0 = x0 or 0
  --y spacing is by default 10, or tighter-packed 8 if style==3
  local yd = style==3 and 8 or 10
  for i=1,#clsts do
    for j,crd in ipairs(clsts[i]) do
      local x=x0+8+(i-1)*spacing
      local y=y0+5+(j-1)*yd
      local tstyle=style
      if (indextable(sellst,crd)) tstyle=4
      local selon = (i==selx and j==sely)
      drawcard(crd,x,y,tstyle,selon)
    end
  end
  --preview one card large (disabled if selx or y <=0)
  if selx>0 and sely>0 then
    local crd=clsts[selx][sely]
    --TODO? generalize this mod-specific code? but works fine for now, minimal tokens
    if (modmode) crd=descmod(crd)
    drawcard(crd,85,24,0,true,true,modmode)
  end
end

--alternative to more complex drawcardsellists():
-- draw a generic simple menu from a text lst
--TODO?: merge this with drawcardsellists() to save tokens?
--       (would have to add this "auto width box" and color parameters to that)
function drawselmenu(lst,x0,y0,c)
  c=c or 6
  for i,str in ipairs(lst) do
    local ym = y0+(i-1)*8
    printmspr(str,x0,ym,c)
    if (sely==i) then
      --selection rectangle auto-sized to content
      --NOTE: does not account for double-width characters or control codes correctly
      rect(x0-2,ym-2,x0+#str*4,ym+6,12)
    end
  end
end

-----
----- 9) miscellaneous helper functions
-----

---- 9a) message queue helper functions:

-- add string or list of strings to message queue
function addmsg(m)
  addflat(msgq,m)
  ----DEBUG tool: log all messages to a file
  --if (type(m)=="table") m=m[1]
  --if (logmsgq) printh(m, 'msgq.txt') --debug
end

function clrmsg()
  msgq={}
  --clear y offset for first new msg
  msg_yd=0
end

---- 9b) misc drawing functions

--filled rectangle with contrasting border
function rectborder(x0,y0,xf,yf,cbk,cbr)
	rectfill(x0,y0,xf,yf,cbk)
	rect(x0,y0,xf,yf,cbr)
end


---- 9c) LOS (line of sight, for ranged attacks)

-- see also: the LOS debugging line() function in drawmapsel()
--           to uncomment during testing

--primitive sort-of-LOS algorithm with known bugs: 
-- Says we have LOS if manhattan distance between a and d ==
--  the A*-calculated "path length to travel between squares if jumping"
-- (this is not correct in some cases but is surprisingly often correct: if there's
--  a wall between two characters, the pathfind distance involves walking around the
--  wall so will be != the manhattan distance)
-- And notably, this is very code-efficient under the tight PICO8 constraints where I
--  was running out of code space, because we reuse the pathfind() function we already have)
-- TODO(BUG): This fails noticeably for long range LOS for example if two actors are at perfect
--  right angles to a door/entryway that connects them but there's otherwise a wall
--  blocking "real" LOS
--function lineofsight(a,d)
----  print(#pathfind(a,d,true).." dst:"..dst(a,d)) --debugging
--  local pth=pathfind(a,d,true)
--  return pth and #pth-1==dst(a,d)
--end

--another LOS test, ~53tok vs the 24tok pseudo lineofsight() above
--draw a virtual line between centers of a and d and 
-- check ~10 points along that line to see if any
-- fall in hexes with the "blocks LOS" sprite flag
function lineofsight(a,d)
  for i=0,1,0.11 do
    if (fget(mget(flr(a.x+i*(d.x-a.x)+0.5),flr(a.y+i*(d.y-a.y)+0.5)),1)) return false
  end
  return true
end

---- 9d) card parsing

-- parse a short single-card string into action, value, etc
--  e.g. "2MJ" -> crd.act="M", crd.val=2, crd.jmp=true, etc 
--       (but replace M, J  above with sh(m),  sh(j) chars)
--TODO? possible to simplify code to reduce tokens?
function parsecard(crdstr)
  local ctbl={}
  if crdstr[-1]=="▒" then
    ctbl.burn=true
    crdstr=sub(crdstr,1,-2) --remove right character
  end
  if tonum(crdstr[2])==nil then
    ctbl.special=true
    ctbl.act=crdstr
    if (crdstr=="smite") ctbl.val,ctbl.rng=20,10
  else
    ctbl.act=crdstr[1]
    ctbl.val=tonum(crdstr[2])
    if #crdstr>=3 then
      ctbl.mod=crdstr[3]
      if #crdstr>=4 then
        if tonum(crdstr[4])==nil then
          ctbl.mod2=crdstr[4]
        else
          ctbl.modval=tonum(crdstr[4])
          if (#crdstr>=5) ctbl.mod2=crdstr[5]
        end
      end
    end
    --preprocess some common properties
    if (ctbl.mod=="웃") ctbl.jmp=true
    ctbl.rng=1
    if (ctbl.mod=="➡️") ctbl.rng=ctbl.modval
    if (crdstr[-1]=="░") ctbl.aoe=8
    if (ctbl.mod=="◆") ctbl.push=ctbl.modval
    if (ctbl.mod=="▥" or ctbl.mod2=="▥") ctbl.stun=true
    if (ctbl.mod=="∧" or ctbl.mod2=="∧") ctbl.wound=true
  end
  return ctbl
end


---- 9e) deck and card helper functions

--generalized 'reshuffle discards' function
-- commented out to save 9 tokens since only
-- ever used to shuffle modifier deck at least in this chapter
-- (enemy actions not currently discarded/shuffled)

--function shuffle(deck,discard)
--  while (#discard>0) do
--    add(deck,deli(discard))
--  end
--end

--function shufflemoddeck()
--  shuffle(pmoddeck,pmoddiscard)
--end

--special-cased "shuffle modifier discards back into deck"
-- note that this is just adding them to the end of the deck, not
-- randomizing the order, since we draw a random card from this deck
-- with rnd(pmoddeck)
function shufflemoddeck()
  --addmsg("(mOD dECK RESHUFFLED)") --TODO: remove, not worth tokens?
  while (#pmoddiscard>0) do
    add(pmoddeck,deli(pmoddiscard))
  end
end

function decksreset()
  for c in all(pdeck) do
    c.status=0
  end
  shufflemoddeck()
end

--return discarded card or item to hand
-- abstracted to function that can be called via foreach()
-- to save some tokens, see for example use in longrest()
function refresh(crd)
  if (crd.status==1) crd.status=0
end

function clearcards(obj)
  obj.crds,obj.init,obj.crd=nil
end


----  9f) array and table helper functions (general-purpose)

function splitarr(arr)
  --split array into two ~half-length arrays
  local arr1={unpack(arr,1,ceil(#arr/2))}
  local arr2={unpack(arr,ceil(#arr/2)+1)}
  return arr1,arr2
end

--find x in tbl[], return index (or nil if not in table)
--if prop is not nil, find x in tbl[][prop] instead
function indextable(tbl,x,prop)
  for i,val in ipairs(tbl) do
    if not prop then
      if (val==x) return i
    else
      if (val[prop]==x) return i
    end
  end
  --implicit "return nil"
end

--hard-coded "sort by init property" routine since that's the
-- only sorting we need to do
function sort_by_init(a)
  --TODO: remove the tonum() if we can ensure player and enemy deck initiatives are numbers in data structs
  for i=1,#a do
      local j=i
--      while j>1 and tonum(a[j-1][key]) > tonum(a[j][key]) do
      while j>1 and tonum(a[j-1].init) > tonum(a[j].init) do
        a[j],a[j-1]=a[j-1],a[j]
          j-=1
      end
  end
end

function xylst(x,y)
  return {x=x,y=y}
end

--count occurances of items in list
--e.g. {a,b,a,a,c} -> {{"a",3},{"b",1},{"c",1}}
function countlist(lst)
  local counted={}
  for itm in all(lst) do
    counted[itm]=(counted[itm] or 0) + 1
  end
  return counted
end

--similar to add(), except if values is a table,
-- or a \n-separated multiline string,
-- add each of its members one by one
function addflat(table, values)
  if type(values)!="table" then
    --split multiline string into table, or
    -- convert singleline string to 1-element table
    values=split(values,"\n")
  end
  for val in all(values) do
    add(table,val)
  end
end

---- 9g) more data structure helper functions (data-specific)

function actorat(x,y)
  --return index into actor[] of the actor at loc
  for i,a in ipairs(actor) do
    if (a.x==x and a.y==y) return i
  end
  return 0
end

--lint: ilist
function initiativelist()
  --create global list of order of enemy and player
  -- initiatives (list of actor[#] indexes)
  --TODO: determine if this can be a local (since we return
  --      it and assign to global ilist), or if that breaks
  --      the sort-in-place sort_by_ilist (if we keep this
  --      as global, could avoid returning and assigning, but
  --      that's less clear)
  ilist={}
  for i,a in ipairs(actor) do
    --first element of first card = initiative
    add(ilist,{init=a.init,id=i,name=a.name})
  end
  sort_by_init(ilist)
  return ilist
end

--wrapper for common item case
function hasitem(itemname,useitem)
  local itemi=indextable(pitems,itemname,"shortname")
  if (not itemi or pitems[itemi].status!=0) return false
  --for items that can only be used once:
  if (useitem) pitems[itemi].status=1
  return true
end

---- 9h) animation helper functions

--queue animation of obj move from x0,y0->x,y
--note/warning: also modifies obj.x and obj.y values 
-- to set equal to destination! (which may be unexpected)
function queueanim(obj,x,y,x0,y0,mspr)
  obj = obj or add(actor,{spr=mspr,noanim=true,ephem=true})
  obj.x,obj.y=x,y
  obj.sox,obj.soy=8*(x0-x),8*(y0-y)
  obj.ox,obj.oy=obj.sox,obj.soy
  animt=0
end

---- 9i) math helper functions

function dst(a, b)
  return abs(a.x - b.x) + abs(a.y - b.y)
end

---- 9j) fog

--init 11x11 map array as "fogged"
--lint: fog
function initfog()
  --minimal-token hard-coded "init all to fog" array
  fog=splt3d("1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1|1;1;1;1;1;1;1;1;1;1;1")
end

--TODO? shift all maps to start at (1,1) on mapboard, 
--  to remove need for the +1s in these fns? (would save ~8tok)
function isfogoroffboard(x,y)
  return (x<0 or x>10 or y<0 or y>10) or fog[x+1][y+1]
end

function unfog(x,y)
  fog[x+1][y+1]=false
end

--set all tiles in same room as (x,y) to unfogged, called
-- on door open, for example
function unfogroom(x,y)
  --naive rectangular algorithm, depends on careful map design and
  -- placement of "unfog limiting obstacles" with proper flags
  --TODO? extend for non-rectangular rooms for future level designs?
  if (fget(mget(x,y),6)) return
  --TODO? could shave off both ,0s to save 2tok if level design is
  -- careful, but introduces risk of crash bug, so don't for now
  local xf,yf,x0,y0=10,10,0,0 
  --find closest "walls" in each direction
  --originally had separate for loops to determine x limits and then y limits.
  -- this single loop is more token efficient but harder to read
  --TODO? look into more token-efficient implementation
  for n=0,10 do
    if fget(mget(n,y),6) then
      if n<x then
        x0=n
      else
        xf=min(n,xf)
      end
    end
    if fget(mget(x,n),6) then
      if n<y then
        y0=n
      else
        yf=min(n,yf)
      end
    end
  end
  for i=x0,xf do
    for j=y0,yf do
      unfog(i,j)
    end
  end
end


-----
----- x) pause menu items
-----

-- DEPRECATED: had options to adjust difficulty,
--  message speed, etc, but trimmed tokens (and moved
--  difficulty selection to town menu)

--menu item for difficulty
--function difficultymenu(b)
--  if (b==1) difficulty-=1
--  if (b==2) difficulty+=1
--  --4 -> #difficparams?
--  difficulty=max(1,min(4,difficulty))
--  menuitem(5,difficparams[difficulty].txt,difficultymenu)
--end

----menu item for message speed
--function msgspeed(b)
--  if b&2>0 then
--    msg_td,animtd=2,0.08
--    menuitem(1, "< speed: fast", msgspeed)
--  elseif b&1>0 then
--    msg_td,animtd=4,0.05
--    menuitem(1, "speed: slow >", msgspeed)
--  end
--end

-----
----- 10) data string -> datastructure parsing + loading
-----

--split a data string separated by ; (workhorse function)
-- skipconv = don't convert to #
-- kv = parse as key/value set (e.g. x;1;y;2-> {x=1,y=2})
--TODO: invert skipconv true/false logic to match split()
function splt(str,skipconv,kv)
  local lst={}
  local s=split(str,";",not skipconv)
  if kv then
    for k=1,#s,2 do
      lst[s[k]]=s[k+1]
    end
    return lst
  end
  return s
end

--split on / and | and ; into an up-to-3D array
-- if kv==true, further split into k/v pairs
-- e.g. splt3d("a;3;b;ab|a;4;b;cd",true) -> 
--            {{a=3,b="ab"},{a=4,b="cd"}}
function splt3d(str,kv)
  local lst1,arr3d=split(str,"/"),{}
  for i,lst2 in ipairs(lst1) do
    add(arr3d,{})
    local arr2d=split(lst2,"|")
    for lst3 in all(arr2d) do
      add(arr3d[i],splt(lst3,nil,kv))
    end
  end
  --remove any unused data layers
  while #arr3d==1 do
    arr3d=arr3d[1]
  end
  return arr3d
end

--read game data stored elsewhere in cart
-- decode a string from cart (typically from spr/sfx mem,
-- to be then run through split/etc to extract table data)
--reads _backwards_ from specified address based on #bytes indicated
-- (so typically would be passed address of end of spr/sfx mem)
--see separate storedatatocart6.p8 cart for usage+storing this data in first place
--uses ~97 tokens including 8-to-6 bit decompression
-- and the decode64_substr=split(...) in initdbs()
--(older but more brittle v5 used ~89 tokens, this is ~8tok more?)

function extractcartdata6_64ng(addr)
  local arr={}
  addr-=1 --prepare to read the 2-byte value "# bytes"
  for i=1,%addr do  -- % is unary peek2
    add(arr,@(addr-i))
  end
  return decode64ng(arr)
end

function decode64ng(arr)
  local str,v,b="",0,0
  for a in all(arr) do
     v=256*v+a
     b+=8
     while b>=6 do
       b-=6
       str..=decode64_substrs[(v>>b&63)+1]
       v=v&(2^b-1)
    end
  end
  return(str)
end


-----
----- 11) inits and databases
-----


--lint: func::_init
function initglobals()
  --TODO? directly substitute these values in where used to save
  --      tokens at the cost of easier future adjustments, as they
  --      haven't changed in a long time
  --(leave commented-out copies of lines w/ these parameters to
  -- make it easier to understand in code)
  map_w,msg_x0,msg_yd,hud_x0,hud_ey,hud_py=92,0,0,93,27,81
  --animation consts
  act_td,afram,fram,animt,wipe=15,0,0,1,0
  msg_td,animtd=3,0.05
  --game configurations
  -- 1=easier, 2=normal, 3=hard, 4=brutal
  difficulty=2      
  mindifficulty=4   --for campaign stats: lowest difficulty level played (ignoring starter level), updated in new level
  difficparams=splt3d("txt;●easier●;hpscale;0.5;gp;1;trapdmg;6|txt;★normal★;hpscale;1;gp;1;trapdmg;6|txt;▥harder▥;hpscale;1.2;gp;2;trapdmg;8|txt;▒brutal▒;hpscale;1.5;gp;2;trapdmg;10",true)
  -----(deprecated) initialize Pause Menu items
  --difficultymenu(0) -- create pause menu item
  --msgspeed(1)  --sets msg_td,animtd

  dirx,diry=split("-1,1,0,0"),split("0,0,-1,1")
  msgq={}
  --campaign stats
  camp_gold,camp_kills,camp_time=0,0,0
  --state inits
  state,prevstate,nextstate="","",""
  --init() function to call for each state
  initfn={newlevel=initnewlevel,splash=initsplash,town=inittown,
          endlevel=initendlevel,newturn=initnewturn,choosecards=initchoosecards,
          precombat=initprecombat,actloop=initactloop,
          actenemy=initactenemy,actplayerpre=initactplayerpre,actplayer=initactplayer,
          actplayermove=initactplayermove,animmovestep=initanimmovestep,
          actplayerattack=initactplayerattack,cleanup=initcleanup,profile=initprofile,
          upgradedeck=initupgrades,upgrademod=initupgrademod,store=initstore,pretown=initpretown}
  --descriptions of card actions, by character
  --TODO? remove redundant ones as these are also manually specified
  --      (for secondary modifiers) in desccard()
  descact=splt3d("█;atk ;😐;move ;♥;heal ;●;gold ;웃;jump;➡️;@ rng ;⬅️;get all\ntreasure\nwithin\nrange ➡️;★;shld ;∧;wound;▥;stun;▒;burn;░;adjacent",true)
end

--initialize a new level
--lint: func::_init
function initlevel()
--  if godmode then
--    --overwrite first card in deck with debug "smite" card
--    pdeck[1]=pdeckmaster[#pdeckmaster-1]
----    p_xp=500
----    p.maxhp=50
-- end  
  --scaling gold and traps with difficulty mode
  gppercoin,trapdmg=difficparams[difficulty].gp,difficparams[difficulty].trapdmg
  herbs=0   --for special alt wincon levels
  --NOTE: currently clearing here (once per level) to allow you to scroll back multiple
  -- turns (comes with extra token cost of pruning the length of this
  -- queue to avoid too much CPU processing)
  clrmsg()  
  copylvlmap(dlvl)
  initfog()
  --init actors, add player as first actor
  actor={p}
  --TODO?: change armor item implementation to increase max hp?
  --       (then could remove code around p.pshld entirely?)
  if (hasitem("mail")) p.pshld=1 --persistent shield
  p.shld,p.stun,p.wound,p.hp=p.pshld,false,false,p.maxhp
  --if (hasitem("mail")) p.hp+=5
   --init player xy and also doors, chests
  initpxy()
  unfogroom(p.x,p.y)
  initactorxys()
  --move queue-- list of steps taken by actor to dest
  mvq={}
  --refresh decks
  decksreset()
  foreach(pitems,refresh)
  --selection info
  selx,sely,showmapsel,selvalid=p.x,p.y,true,false  --could omit last ,false to save token?
  --TODO: Remind myself and document what this line does
  enemytype[#enemytype].id=#enemytype
  --reset cards and initiative
  foreach(enemytype,clearcards)
  tutorialmode=dlvl<=2 --in tutorial mode extra strings are shown
  --clrmsg()
  levelstarttime=time() --global, for campaign stats
end

--copy map for level l to the (0,0)->(10,10) region of map,
-- so all other game functions don't need to track a level-based
-- map offset and can just refer to that
function copylvlmap(l)
  for i=0,10 do
    for j=0,10 do
      mset(i,j,mget(i+lvls[l].x0,j+lvls[l].y0))
    end
  end
end

--locate player on map and set x,y variables
--also initialize # of doors and cleared chests in this map
--TODO? could hard-code this info in each level design DB,
-- saving ~40 tokens but taking effort to keep in sync w/ map,
-- not worth the hassle unless those tokens are desperately needed
--lint: doorsleft
function initpxy()
  doorsleft=0
  for i=0,10 do
    for j=0,10 do
      if mget(i,j)==1 then  --found player start
        mset(i,j,33)
        p.x,p.y=i,j
      end
      if (fget(mget(i,j),7)) doorsleft+=1
      --TODO (commented out, insufficient tokens for now)
      --if we already cleared chest for this level and are
      -- replaying it (e.g. failed level), remove chest...
      --if (lvls[dlvl].chestcleared and mget(i,j)==37) mset(i,j,33)
    end
  end
end

--initialize all actors in unfogged parts of map
--NOTE: removed fget check for flag 0 and moved isfogoroffboard() check
--      into et.spr line: saved ~9 tokens at cost of more 
--      processing by running each time in loop 
--       (could reinstate if needed but seems fine)
function initactorxys()
  for i=0,10 do
    for j=0,10 do
--      if fget(mget(i,j),0) and not isfogoroffboard(i,j) then
        for e,et in ipairs(enemytype) do
          if (et.spr==mget(i,j) and not isfogoroffboard(i,j)) then
            mset(i,j,33)
            --TODO? (WIP draft): only initialize a fraction of the
            --      enemies for special "randomized levels"
            --      (only imagined for repeatable+grindable side quests)
            --      would take ~20 tokens:
--            local ernd=lvls[dlvl].rndlvl
--            if (#actor>1 and ernd and rnd()>ernd) return
            initenemy(e,i,j)
          end
        end
--      end
    end
  end
end

--create instance of enemytype[n] at x,y
function initenemy(n,x,y)
  local etype=enemytype[n]
  local en={type=etype,x=x,y=y,
      ox=0,oy=0,sox=0,soy=0,
--      maxhp=etype.maxhp,  --simpler pre-difficulty-setting method
      --scale maxhp based on difficulty (but round up, so maxhp won't be < 1)
      maxhp=ceil(etype.maxhp*difficparams[difficulty].hpscale),
      spr=etype.spr,
      name=etype.name,
      obj=etype.obj,  --object that doesn't drop gold
      pshld=etype.pshld}
  en.shld,en.hp=en.pshld,en.maxhp
  add(actor,en)
  --TODO?: check if it saves tokens (now that we have so many
  --       properties) to do a loop,e.g.
  --         for k,v in pairs(etype) do en.k=v end 
  --       but would have various special cases...
end

--initiatize major databases of level, enemy, player information
--
--much of this created in an external spreadsheet for easier editing, 
-- which then joins the values into these nested or key-value arrays
--lint: func::_init
function initdbs()
  --- init level dbs (long string)
  lvls=splt3d("name;test level;x0;0;y0;0;unlocks;1;xp;10;gp;0|name;forest;x0;11;y0;0;unlocks;3;xp;10;gp;0|name;funeral;x0;22;y0;0;unlocks;4;xp;60;gp;20|name;ruined chapel;x0;33;y0;0;unlocks;5,6;xp;10;gp;5|name;forest hovel;x0;44;y0;0;unlocks;7;xp;10;gp;0|name;investigate inn;x0;55;y0;0;unlocks;;xp;10;gp;0|name;town cemetery;x0;66;y0;0;unlocks;8;xp;10;gp;0|name;hero mausoleum;x0;77;y0;0;unlocks;9,10,12;xp;50;gp;0|name;pelt collecting (side job);x0;88;y0;0;unlocks;10;xp;5;gp;25|name;rampaging bear  (side job);x0;99;y0;0;unlocks;11;xp;20;gp;0|name;strange noises  (side job);x0;88;y0;11;unlocks;9;xp;20;gp;5|name;council meeting;x0;110;y0;0;unlocks;13;xp;10;gp;20|name;mossy cottage;x0;11;y0;11;unlocks;14;xp;10;gp;0|name;fetid swamp;x0;22;y0;11;unlocks;15;xp;10;gp;0|name;outer cemetery;x0;33;y0;11;unlocks;16;xp;10;gp;0|name;inner cemetery;x0;44;y0;11;unlocks;17;xp;50;gp;30|name;* victory *;x0;55;y0;11;unlocks;18;xp;20;gp;0|name;twisted grove;x0;66;y0;11;unlocks;19;xp;10;gp;0|name;roadside shrine;x0;77;y0;11;unlocks;20,21;xp;10;gp;10|name;mountain vault (side quest);x0;0;y0;11;unlocks;;xp;10;gp;0|name;mountain maze;x0;99;y0;11;unlocks;22;xp;10;gp;0|name;ritual chamber;x0;110;y0;11;unlocks;;xp;50;gp;0",true)
  --TEMP version that ends the campaign after lvl8, for external testers
  --lvls=splt3d("name;test level;x0;0;y0;0;unlocks;1;xp;10;gp;0|name;forest;x0;11;y0;0;unlocks;3;xp;10;gp;0|name;funeral;x0;22;y0;0;unlocks;4;xp;60;gp;20|name;ruined chapel;x0;33;y0;0;unlocks;5,6;xp;10;gp;5|name;forest hovel;x0;44;y0;0;unlocks;7;xp;10;gp;0|name;investigate inn;x0;55;y0;0;unlocks;;xp;10;gp;0|name;town cemetery;x0;66;y0;0;unlocks;8;xp;10;gp;0|name;hero mausoleum;x0;77;y0;0;unlocks;;xp;50;gp;0|name;pelt collecting (side job);x0;88;y0;0;unlocks;10;xp;5;gp;25|name;rampaging bear  (side job);x0;99;y0;0;unlocks;11;xp;20;gp;0|name;strange noises  (side job);x0;88;y0;11;unlocks;9;xp;20;gp;5|name;council meeting;x0;110;y0;0;unlocks;13;xp;10;gp;20|name;mossy cottage;x0;11;y0;11;unlocks;14;xp;10;gp;0|name;fetid swamp;x0;22;y0;11;unlocks;15;xp;10;gp;0|name;outer cemetery;x0;33;y0;11;unlocks;16;xp;10;gp;0|name;inner cemetery;x0;44;y0;11;unlocks;17;xp;50;gp;30|name;* victory *;x0;55;y0;11;unlocks;18;xp;20;gp;0|name;twisted grove;x0;66;y0;11;unlocks;19;xp;10;gp;0|name;roadside shrine;x0;77;y0;11;unlocks;20,21;xp;10;gp;10|name;mountain vault (side quest);x0;0;y0;11;unlocks;;xp;10;gp;0|name;mountain maze;x0;99;y0;11;unlocks;22;xp;10;gp;0|name;ritual chamber;x0;110;y0;11;unlocks;;xp;50;gp;0",true)
  --unlock starting level
  lvls[dlvl].unlocked=1

  --for extractcartdata decoding (see storedatatocart5.p8 for details)
  --decode64_foo needs to be indexable:
  -- either a string with one character per token,
  -- or a split("a|b|the|...","|") series of variable-length ngrams
--  decode64_chrs=" \n().',:!?-;28/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghilmnopqrstvwxy"
  decode64_substrs=split("\n| |!|'|(|)|,|-|.|/|2|:|;|?|A|B|C|D|E|F|G|H|I|J|K|L|M|N|O|P|Q|R|S|T|U|V|W|X|Y|Z|a|b|c|d|e|f|g|h|i|m|n|o|p|q|r|s|t|v|w|y|THE |OU|S |D ","|",false)
  --extract wordy level story text stored in unused spr/sfx mem
  pretxt=splt(extractcartdata6_64ng(0x42ff))
  fintxt=splt(extractcartdata6_64ng(0x1fff))

  --- init enemy dbs
  --enemy types: data string compiled from separate spreadsheet
  enemytype=splt3d("id;1;name;skel;spr;64;maxhp;4;pshld;0|id;2;name;zomb;spr;68;maxhp;8;pshld;0|id;3;name;skel+;spr;72;maxhp;6;pshld;1|id;4;name;zomb+;spr;76;maxhp;12;pshld;0|id;5;name;sklar;spr;80;maxhp;3;pshld;0|id;6;name;cult;spr;84;maxhp;6;summon;1;pshld;0|id;7;name;bndt;spr;130;maxhp;8;pshld;0|id;8;name;wolf;spr;88;maxhp;5;pshld;0|id;9;name;warg;spr;92;maxhp;9;pshld;1|id;10;name;tree;spr;96;maxhp;8;pshld;0|id;11;name;spdr;spr;100;maxhp;1;pshld;0|id;12;name;orb;spr;104;maxhp;6;pshld;0;obj;1|id;13;name;grav;spr;108;maxhp;1;summon;4;pshld;2;obj;1|id;14;name;grav ;spr;112;maxhp;1;summon;4;pshld;2;obj;1|id;15;name;rat;spr;116;maxhp;2;pshld;0|id;16;name;bear;spr;134;maxhp;70;pshld;0|id;17;name;golem;spr;120;maxhp;8;pshld;5|id;18;name;shdw;spr;52;maxhp;5;summon;18;pshld;0|id;19;name;shdw+;spr;56;maxhp;8;summon;18;pshld;0|id;20;name;noah;spr;60;maxhp;24;summon;19;pshld;8|id;21;name;hero;spr;124;maxhp;20;pshld;0|id;22;name;hero+;spr;125;maxhp;24;pshld;1|id;23;name;hero*;spr;126;maxhp;99;pshld;9",true)
  --enemy action decks (options) from separate spreadsheet
  edecksstr="init;57;act;😐3|act;█3/init;60;act;😐1|act;█4/init;30;act;😐2|act;♥2/init;21;act;😐3|act;█2/init;19;act;😐2|act;█2,init;78;act;█7/init;72;act;😐1|act;█4/init;56;act;😐1|act;█2∧/init;67;act;😐1|act;█5,init;57;act;😐4|act;█4/init;60;act;😐2|act;█5/init;30;act;😐3|act;♥3/init;21;act;😐4|act;█3/init;19;act;😐3|act;█3,init;78;act;█8/init;72;act;😐1|act;█7/init;56;act;😐2|act;█4∧/init;67;act;😐1|act;█6∧,init;21;act;😐1|act;█2➡️3/init;40;act;█3➡️3/init;50;act;😐1|act;█1➡️4∧/init;70;act;😐1|act;█3➡️3/init;37;act;😐2|act;█1➡️3,init;40;act;😐1|act;█1/init;30;act;😐1|act;█2/init;90;act;call,init;54;act;😐1|act;█4/init;44;act;😐2|act;█3/init;34;act;😐3|act;█2/init;51;act;😐3|act;█2➡️2/init;22;act;★2|act;█3/init;36;act;★2|act;♥2,init;65;act;howl/init;11;act;😐4|act;█3/init;22;act;😐5|act;█2/init;35;act;😐4|act;█2∧,init;60;act;howl/init;8;act;😐4|act;█4∧/init;17;act;😐5|act;█2∧/init;20;act;😐4|act;█3∧,init;60;act;█4/init;72;act;█3/init;80;act;█5/init;64;act;█2➡️3,init;10;act;😐1|act;█1▥/init;24;act;😐2|act;█1▥/init;14;act;😐2|act;█1/init;26;act;😐1|act;█2,init;99;act;♥1/init;99;act;♥1,init;99;act;♥1/init;99;act;♥1/init;50;act;call,init;99;act;♥1/init;99;act;♥1/init;99;act;♥1/init;99;act;♥1/init;50;act;call,init;22;act;😐3|act;█1/init;38;act;😐3|act;█1/init;32;act;😐2|act;█2/init;35;act;😐1|act;█2,init;18;act;😐2|act;█3∧/init;52;act;😐3|act;█5∧/init;57;act;😐3|act;█5∧/init;68;act;😐2|act;█8∧,init;50;act;😐2|act;█4/init;50;act;😐2|act;█4/init;50;act;😐2|act;█4/init;50;act;😐2|act;█4/init;50;act;😐2|act;█4➡️2,init;40;act;😐2|act;█3/init;53;act;😐3|act;█2/init;70;act;♥2|act;█2➡️2/init;90;act;call,init;53;act;😐1|act;█2➡️3/init;70;act;♥1|act;█2➡️4/init;90;act;call,init;39;act;😐2|act;█3➡️4/init;52;act;😐1|act;█2➡️4/init;69;act;♥1|act;█1➡️6/init;60;act;😐2|act;█2➡️5/init;43;act;😐1|act;█1➡️5▥/init;80;act;😐2|act;call/init;80;act;😐3|act;call,init;15;act;😐2|act;█4/init;15;act;😐2|act;█2➡️3/init;35;act;😐3|act;█3/init;23;act;★2|act;█2➡️3/init;65;act;♥4|act;█2/init;70;act;😐3|act;█5➡️2,init;15;act;😐2|act;█4/init;15;act;😐2|act;█3➡️3/init;17;act;😐2|act;█2▥/init;11;act;★4|act;█3➡️3/init;73;act;😐6|act;█3∧/init;31;act;😐5|act;█6/init;65;act;♥4|act;█2/init;48;act;★4|act;█7▥,init;15;act;😐2|act;█4/init;15;act;😐2|act;█3➡️3/init;17;act;😐2|act;█2▥/init;11;act;😐4|act;█3➡️3/init;73;act;😐6|act;█3∧/init;31;act;😐5|act;█6/init;65;act;😐3|act;♥4/init;48;act;😐4|act;█7▥"
  --for 4d nested data, split the above string in two passes:
  --TODO? move below into splt3d() as a more general splitting? Maybe w/o "," sep?
  edecks={}
  for ed in all(split(edecksstr)) do
    add(edecks,splt3d(ed,true))
  end

  --- init player dbs (and upgrades)
  --player info
  p=splt3d("name;you;spr;2;maxhp;10;hp;10;pshld;0;shld;0;ox;0;oy;0;sox;0;soy;0",true)
  --set a few unique-to-player-actor properties as globals
  -- to save a few tokens where used compared to p.xp, p.gp, etc
  p_xp,p_gp,p_lvl=0,10,1

  --all potential player cards, combining the starting N plus 2 upgrades/level
  -- plus a 'god mode' card beyond the L9 upgrades, only used for testing
  -- string created in separate spreadsheet
  pdeckmaster=splt3d("init;13;act;😐3;status;0;name;\n  dash|init;22;act;█2;status;0;name;\n  slice|init;42;act;█3;status;0;name;\n  chop|init;31;act;😐4웃▒;status;0;name;\n  leap|init;32;act;█3➡️3;status;0;name;\n dart|init;28;act;█2◆2;status;0;name;\n thrust|init;55;act;█2➡️5;status;0;name;\n volley|init;54;act;█5➡️4▒;status;0;name;\n missile|init;36;act;♥4▒;status;0;name; first\n  aid|init;74;act;😐3;status;0;name;\nshuffle|init;85;act;⬅️2;status;0;name;  loot\nlocally|init;45;act;█3∧;status;0;name;\n slash|init;25;act;😐5;status;0;name;\nsidestep|init;20;act;█2◆4;status;0;name;\n  bash|init;33;act;█1➡️4░;status;0;name; arrow\n spray|init;10;act;★5;status;0;name; shield\n  self|init;30;act;█2∧░;status;0;name;spinning\n blades|init;25;act;█2➡️6▥;status;0;name;numbing\n  venom|init;13;act;😐9웃▒;status;0;name; artful\nparkour|init;46;act;█3➡️5∧;status;0;name;piercing\n missile|init;75;act;⬅️5▒;status;0;name; gather\ngreedily|init;36;act;♥5;status;0;name; herbal\n remedy|init;21;act;█3◆6;status;0;name;  judo\n throw|init;26;act;█8∧▒;status;0;name; razor\n trap|init;58;act;█3➡️4░;status;0;name;blot out\n the sun|init;62;act;█3▥░;status;0;name;stinging\n  shivs|init;34;act;█6➡️5;status;0;name; doomed\n quarrel|init;10;act;smite;status;0;name;\n smite\n\n\f6divine\n torrent\n of hail\n\n\f8(debug\n assist)|init;99;act;rest;status;0;name;  long\n  rest\n\n\f6heal 3\n\n\|drefresh\n items\n\n\|d\f8burn\f6 the\n2nd card\n chosen",true)
--  --debug version w/ very long range atks for LOS testing
--  pdeckmaster=splt3d("init;13;act;😐3;status;0;name;\n  dash|init;22;act;█2;status;0;name;\n  slice|init;42;act;█3;status;0;name;\n  chop|init;31;act;😐4웃▒;status;0;name;\n  leap|init;32;act;█3➡️7;status;0;name;\n dart|init;28;act;█2◆2;status;0;name;\n thrust|init;55;act;█2➡️9;status;0;name;\n volley|init;54;act;█5➡️4▒;status;0;name;\n missile|init;36;act;♥4▒;status;0;name; first\n  aid|init;74;act;😐3;status;0;name;\nshuffle|init;85;act;⬅️2;status;0;name;  loot\nlocally|init;45;act;█3∧;status;0;name;\n slash|init;25;act;😐5;status;0;name;\nsidestep|init;20;act;█2◆4;status;0;name;\n  bash|init;33;act;█1➡️4░;status;0;name; arrow\n spray|init;10;act;★5;status;0;name; shield\n  self|init;30;act;█2∧░;status;0;name;spinning\n blades|init;25;act;█2➡️6▥;status;0;name;numbing\n  venom|init;13;act;😐9웃▒;status;0;name; artful\nparkour|init;46;act;█3➡️5∧;status;0;name;piercing\n missile|init;75;act;⬅️5▒;status;0;name; gather\ngreedily|init;36;act;♥5;status;0;name; herbal\n remedy|init;21;act;█3◆6;status;0;name;  judo\n throw|init;26;act;█8∧▒;status;0;name; razor\n trap|init;58;act;█3➡️4░;status;0;name;blot out\n the sun|init;62;act;█3▥░;status;0;name;stinging\n  shivs|init;34;act;█6➡️5;status;0;name; doomed\n quarrel|init;10;act;smite;status;0;name;\n smite\n\n\f6divine\n torrent\n of hail\n\n\f8(debug\n assist)|init;99;act;rest;status;0;name;  long\n  rest\n\n\f6heal 3\n\n\|drefresh\n items\n\n\|d\f8burn\f6 the\n2nd card\n chosen",true)
  --hard-coded pointer to 'long rest' card as last in deck
  longrestcrd=pdeckmaster[#pdeckmaster]
  --initialize starting player deck
  pdeck={}
  pdecksize=11
  for i=1,pdecksize do
    add(pdeck,pdeckmaster[i])
  end
  sort_by_init(pdeck) --sort by initiative for easier viewing
  --player modifier deck (original)
  pmoddeck=splt("/2;-2;-1;-1;-1;-1;+0;+0;+0;+0;+0;+0;+1;+1;+1;+1;+2;*2",true)
  pmoddiscard={}
  --all potential mod upgrades, combining the starting set
  --(first pmodupgradessize items) and then add one more per lvl
  pmodupgradesmaster=splt("-2;-1;-1>+0;+0;+0>+1;>+1;+0>+2;+1>+2;+0>+1∧;+0>+2;+0;+1>+3;>+2;>+1∧;-1",true)
  pmodupgrades={}
  pmodupgradessize=7
  for i=1,pmodupgradessize do
    add(pmodupgrades,pmodupgradesmaster[i])
  end
  pmodupgradesdone={}

  ---init equipment dbs (also from spreadsheet)
  storemaster=splt3d("init;60;act;😐 swift   \-f●60;status;0;name; swift\n boots\n\n\f6default\n 😐2 is\n now 😐3;icon;😐;shortname;swift|init;60;act;い life    ●60;status;0;name;  life\n charm\n\n\f6negate a\n killing\n blow\n\n(refresh\n on long\n rest);icon;い;shortname;life|init;50;act;웃 belt    ●50;status;0;name; winged\n  belt\n\n\f6default\n 😐 move\n also\n 웃 jumps;icon;웃;shortname;belt|init;70;act;➡️ quivr   \-f●70;status;0;name;endless\n quiver\n\n\f6default\n █2 atk\n is now\n █2➡️3;icon;➡️;shortname;quivr|init;60;act;う goggl   \-f●60;status;0;name;  keen\ngoggles\n\n\f6+3➡️ rng\n for all\n ranged\n attacks;icon;う;shortname;goggl|init;40;act;★ shld    ●40;status;0;name; great\n shield\n\n\f6★2 first\n round\n attackd\n\n(refresh\n on long\n rest);icon;★;shortname;shld|init;90;act;お razor   \-f●90;status;0;name; razor\n tips\n\n\f6+1█ dmg\n to all\n ranged\n attacks;icon;お;shortname;razor|init;150;act;え mail    ●150;status;0;name; great\n  mail\n\n\f6permnent\n +★1;icon;え;shortname;mail|init;;act;done;status;0;name;\n  done\n\n\f6return\nto town;icon;;shortname;done",true)
  store={}
  for item in all(storemaster) do
    add(store,item)
  end
  pitems={}
end

-----
----- 12) profile / character sheet
-----

---- state: view profile

function initprofile()
  selx=0  --ensure cursor is off-screen when drawn
  _updstate,_drwstate=_updprofile,_drawprofile
  --_updstate,_drwstate=_updprofile,_drawretire --quick hack to proofread layout of retire screen during dev
end

--TODO? refactor how items are displayed
--      (currently has hack to display item list near right 
--       of screen so "cost" built into name is drawn off-screen)
function _drawprofile()
  rectborder(0,0,127,127,5,13)
  --lots of printing embedded in one long string to save tokens
  printmspr("\f7hunter\f6\*3 ♥ \f6"..p.maxhp.."    \f7lVL \f6"..p_lvl.."/9\n\*9 ● \f6"..p_gp.."    \f7xp   \-e\f6"..p_xp.."/"..tostr(min(p_lvl*80,640)).."\n\n\n\|e\f6aCTIONS:    \-fmODS:        \-fiTEMS:\n\n\n\n\n\n\n\n\n\n\n\n\n\n\*b \|ecAMPAIGN tOTALS:\n\n\|b\*b █"..camp_kills.." ●"..camp_gold.." か"..tostr(camp_time\10).."MIN",7,6)
  line(1,24,126,24,13)
  drawcardsellists({pdeck,countedlststr(pmoddeck),pitems},-2,31,nil,3,42)
end

--summarize # of each item in a list, into list of strings.
--e.g. {1,2,1,1,3} -> {"3x 1","1x 2","1x 3"}
function countedlststr(arr)
  local sumdeck,lst = countlist(arr),{}
  for mod,qty in pairs(sumdeck) do
    add(lst,"\f5"..qty.."x \f6"..mod)
  end
  return lst
end

function _updprofile()
  if (btnp(🅾️)) changestate(prevstate)
end

-----
----- 13) splash screen / intro
-----

--lint: splashmenu, _updstate, _drwstate
function initsplash()
  _updstate,_drwstate=_updsplash,_drawsplash  
  splashmenu={"sTART nEW gAME"}
  --selx,sely=1,1 --not needed as set in changestate()
  if (dget2(0)>0) add(splashmenu,"cONTINUE gAME",1)
  --TODO? (WIP draft): explore 'blessed game' start option once you've
  -- won at least once, to start with extra xp/gold
  -- would take ~21 tokens between this line and updsplash below
--  if camp_wins>0 then
--    add(splashmenu,"nEW gAME (bLESSED)")
--  end
end

function _updsplash()
  selxy_update_clamped(1,#splashmenu)
  if btnp(🅾️) then
    if splashmenu[sely]=="cONTINUE gAME" then
      load_game()
      changestate("town")
    else
--      --TODO? (WIP draft): special blessed game mode (see initsplash())
--      if splashmenu[sely]=="nEW gAME (bLESSED)" then
--        p_gp,p_xp=120,80
--      end
      dset2(0,0)  --overwrite existing saved game by setting saveversion to 0
      --TODO? replace above with memset(foo,0,256) to zero out savegame data?
      --      (not needed but cleaner... but wouldn't want to overwrite
      --       camp_wins if that's used anywhere)
      changestate("newlevel")
    end
  end
end

function _drawsplash()
  if fram%10==0 then
    cls(1)
    print("\*f \*c \f0V1.0a\f6\n\n\*5 \|d\^i\^t\^w\^b\fcpicohaven 2\^-w\^-t\^-i\n\*b \fd\^i\015BY ICEGOAT\014\^-i\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\|b\fd\*2 \015CONTROLS:\014\n\|b\n\*6 \-e\fcさし\fd,\fc🅾️\fd:\-fsELECT\fd  \fc❎\fd:\-fcANCEL\n\*9 \-f(\fcZ\fd)\*8 \-d(\fcX\fd)",0,1)
    drawselmenu(splashmenu,38,84,7)
    map(121,0,36,36,7,5)
    drawcard("█2➡️5",8,45)
    drawcard("😐3웃",8,56)
--    rect(63,0,64,127,15) --debug centering

---- animated stars (commented out to save 15 tokens)
--    for i=1,20 do
--      pset(rnd(128),rnd(128),5)
--    end
  end
end

-----
----- 14) levelup, upgrades
-----

-- upgrade action deck --

--lint: selc,upgradelists
function initupgrades()
  p.maxhp+=1  -- +1 hp per level (less generous than the PICOhaven 1 class)
  --p.maxhp+=1+p_lvl%2  --alternating +2hp, +1,+2,+1 with each level (PICOhaven 1 class)
  p_lvl+=1
  addmsg("uPGRADE aCTION dECK::\n cHOOSE UPGRADE AND\n A CARD TO REPLACE")
  setprompt("\*c \-f\fcさし🅾️\f6:cONFIRM")
  selx,selc=2,{{},{}} --sely already set=1 in standard changestate()
  msg_x0,msg_w=44,84
  --list of existing deck and the 2 available upgrades
  upgradelists={pdeck,pdeckupgrades(p_lvl)}
  _updstate,_drwstate=_updupgradedeck,_drawupgrades
end

--return the array of two cards available for level LVL upgrade
function pdeckupgrades(lvl)
  return {pdeckmaster[pdecksize+2*lvl-3],pdeckmaster[pdecksize+2*lvl-2]}
end

--player selects a card in existing deck and an upgrade
-- card to replace it (no confirmation step: once two are
-- selected the upgrade is performed)
function _updupgradedeck()
  selxy_update_clamped(2,#pdeck)
  sely=min(sely,#upgradelists[selx])
  if btnp(🅾️) then
    local c=upgradelists[selx][sely]
    if selc[selx]==c then
      --if chose existing selection, deselect
      selc[selx]={}
    else
      --assign selection from this column
      selc[selx]=c
    end
    local c1,c2=selc[1],selc[2]
    if c1.init and c2.init then
      --one card from each column selected...
      addmsg(c1.act.."  ->  "..c2.act)
      add(pdeck,c2)
      del(pdeck,c1)
      sort_by_init(pdeck) --re-sort by initiative, in place
      changestate("upgrademod")
    end
  end
end

-- upgrade mod deck
function initupgrademod()
  --add one more upgrade option each level
  addmodupgrade(p_lvl)
  addmsg("uPGRADE YOUR DECK\n OF mODIFIER cARDS:")
  setprompt("\*c \-f\fcし🅾️\f6:cONFIRM")
  selx,selc=2,{}  --sely already reset to 1 in changestate
  msg_x0,msg_w=44,84  --TODO: could comment out? no, gets reset
  upgradelists={countedlststr(pmoddeck),pmodupgrades}
  _updstate,_drwstate=_updupgrademod,_drawupgrades
end

--each new level adds one new mod card upgrade option
--(pool size should stay constant since you use one with
-- each levelup)
--this can also be called in a loop by save_game() to restore
-- the state of this upgrade deck
function addmodupgrade(lvl)
  add(pmodupgrades,pmodupgradesmaster[pmodupgradessize+lvl-1])
end

function _updupgrademod()
  selxy_update_clamped(2,#pmodupgrades,2)
  if btnp(🅾️) then
    local mod=pmodupgrades[sely]
    upgrademod(mod)
    changestate("town")
  end
end

--shared draw function for "upgradedeck" and "upgrademod" states since
-- they are similar. uses global upgradelists
function _drawupgrades()
  clsrect(5)
  printmspr("\f6deck:    \-eupgrades:",15,5)
  drawcardsellists(upgradelists,0,10,selc,0,nil,state=="upgrademod")
  drawmsgbox()
end

-- process a mod string like "-1>+0" to edit the player mod
--  deck and remove from upgrade deck
function upgrademod(mod)
  local _unuseddesc,rc,ac=descmod(mod)
  if (rc) del(pmoddeck,rc)
  if (ac) add(pmoddeck,ac)
  del(pmodupgrades,mod)
  add(pmodupgradesdone,mod)
end

--generate text description of what a mod upgrade
-- will do, to show player
function descmod(mod)
  local strs,rc,ac="summary:\n"
  if mod[1]!=">" then
    rc=sub(mod,1,2)
    strs..="\nremove\n mod "..rc
    mod=sub(mod,3)
  end
  if #mod>0 and mod[1]==">" then
    ac=sub(mod,2)
    strs..="\n\nadd\n mod "..ac
  end
  return strs,rc,ac
end

-----
----- 15) town and retirement
----- 

--lint: townmsg, townlst
function inittown()
  --if (prevstate=="splash" or prevstate=="pretown") music(0)
  save_game()
  --selx,sely=1,1 --not needed as reset in changestate()
  townmsg="yOU RETURN TO THE TOWN OF pICOHAVEN. "
  --create list of town actions
  townlst=splt("vIEW pROFILE;rEVIEW sTORY;sHOP FOR gEAR")
  if p_xp>=p_lvl*80 and p_lvl < 9 then
    townmsg..="yOU HAVE GAINED ENOUGH xp TO lEVEL uP! "
    add(townlst,"* lEVEL uP *",1)	
  end
  if wongame==1 then
    add (townlst,"* retire *",1)
  else
    --create list of accessible levels
    for lvl in all(lvls) do
      if (lvl.unlocked==1) add(townlst,"->"..lvl.name)
    end
  end
  add(townlst,"cHANGE dIFFICULTY: "..difficparams[difficulty].txt)
  _updstate,_drwstate=_updtown,_drawtown
end

function _drawtown()
  cls(5)
  print("\f7  wHAT nEXT?\015\|9\f0\^w\^t\*4 ⌂ ⌂\n\n\*a \-c⌂  ⌂\n\*c ⌂\n\n\n\n\014",0,36)
  printwrap(townmsg,29,8,8,6)
  line(8,43,68,43,7)
  drawselmenu(townlst,8,48)
end

--lint: lastlevelwon
function _updtown()
  selxy_update_clamped(1,#townlst)
  if btnp(🅾️) then
    local sel=townlst[sely]
    if sel=="vIEW pROFILE" then
      changestate("profile")
    elseif sel=="rEVIEW sTORY" then
      --display end-of-previous-level text (for last level won)
      -- "if (lastlevelwon)" handles an edge case where you've 
      --  never won a level yet are in town (i.e. you've failed the opening
      --  tutorial level and gone to town)
      if (lastlevelwon) mapmsg=fintxt[lastlevelwon]
      dlvl=lastlevelwon --ensure correct title shown in review
      clrmsg()
      changestate("pretown")
    elseif sel=="* lEVEL uP *" then
      --this state will also levelup p_lvl, p.maxhp
      changestate("upgradedeck")
    elseif sel=="* retire *" then
      --TODO? If spare tokens free up, create a "retire" state for code consistency
      -- below is a quick more token-efficient but less consistent way
      -- to draw a retire screen we can exit without overhead of a new state
      _drwstate=_drawretire
      nextstate="town"
      _updstate=_upd🅾️
    elseif sel=="sHOP FOR gEAR" then
      changestate("store")
    elseif sub(sel,1,2)=="->" then
      dlvl=indextable(lvls,sub(sel,3),"name")
      mindifficulty=min(mindifficulty,difficulty)
      changestate("newlevel")
    elseif sub(sel,1,10)=="cHANGE dIF" then
      difficulty=difficulty%4+1
      townlst[#townlst] = "cHANGE dIFFICULTY: "..difficparams[difficulty].txt
      save_game()
    end
  end
end

--store
function initstore()
  addmsg("yOU BROWSE THE STORE..")
  setprompt("\fcし🅾️\f6:sELECT")
  --selx,sely=1,1 --not needed as reset in changestate()
  --if (godmode) p_gp=999
  _updstate,_drwstate=_updstore,_drawstore
end

function _updstore()
  --note: as a token-saving hack, item{} reuses the card{}
  --      data structure, except the .init field is used to hold
  --      item cost (since item initiative isn't relevant)
  selxy_update_clamped(1,#store)
  if btnp(🅾️) then
    local item=store[sely]
    if item.act=="done" then
      changestate("town")
    elseif p_gp<item.init then
      addmsg("nOT ENOUGH gOLD.")
    else
      addmsg("yOU BOUGHT "..item.shortname)
      add(pitems,item)
      del(store,item)
      p_gp-=item.init
    end
  end
end

--TODO? implement different way to show prices?
--      (current hack embeds them in item names...)
function _drawstore()
  clsrect(5)
  drawcardsellists({store},0,0)
  printmspr("\f7you have:\n ●"..p_gp,86,6)
  drawmsgbox()
end

--fully end-of-game
function _drawretire()
  --fillp(⌂\1|0b.011)
  fillp(-20192.625) --more token-efficient version of the above
  rectfill(0,0,127,127,6)
  fillp()
  rectfill(8,8,119,119,5)
  printwrap(fintxt[#fintxt],26,12,12,6) --retirement text
  printmspr("\f7cAMPAIGN sTATS ("..difficparams[mindifficulty].txt..")\n █kILLS: \fc"..camp_kills.."\n ●gOLD:   \-e\fc"..camp_gold.."\f6\n かtIME:   \-e\fc"..tostr(camp_time\600).."\f6H\fc"..tostr(camp_time\10%60).."\f6MIN",12,70)
  --TODO? could save 10 tokens w/ simpler minutes-only time formatting:
  --printmspr("\f7cAMPAIGN sTATS ("..difficparams[mindifficulty].txt.."):\n █kILLS: \fc"..camp_kills.."\n ●gOLD:   \-e\fc"..camp_gold.."\f6\n かtIME:   \-e\fc"..tostr(camp_time\10).."\f6MIN",12,92)
end

-----
----- 16) debugging + testing functions
-----     [comment out near release if tokens needed]
-----

--function to build up a stat(1) {cpu % frame usage} string for debugging
-- and characterizing performance / execution time of various subsets of code
--requires: statstr has been defined earlier, and existance of a
-- print(statstr) commnand at end of draw: see similar commented-out code

--function addstat1()
--  statstr..=tostr(stat(1)*100\1).."% "
--end


----table debug, 58tok
---- often called as print(dump(tblofinterest))

--function dump(o)
--  if type(o) == 'table' then
--    local s = '{ '
--    for k,v in pairs(o) do
--        if (type(k) ~= 'number') k = tostr(k)
--        s = s .. '['..k..'] = ' .. dump(v) .. ','
--    end
--    return s .. '} '
--  else
--    return tostring(o)
--  end
--end

-----
----- 17) pathfinding (A*)
-----

--return move queue from [a]ttacker to [d]efender
--if jmp, allow jump (move through obstacles), currently
--  only used for a hacky LOS test but would be needed for
--  jumping/flying enemies if they existed
function pathfind(a,d,jmp,allyblocks)
  --set which "allowable neighbors" function to use in A* path_find()
  local neighborfn=valid_emove_neighbors
  --  if (jmp) neighborfn=valid_emove_neighbors_jmp
  --  if (allyblocks) neighborfn=valid_emove_neighbors_allyblocks
  if (jmp) neighborfn=function(node) return valid_emove_neighbors(node,false,true) end
  if (allyblocks) neighborfn=function(node) return valid_emove_neighbors(node,false,false,true) end
  return find_path(a,d,dst,neighborfn)
end

--- pathfinder (based on code by @casualeffects, with some small mods)
function find_path(start,goal,estimate,neighbors,graph)
  local shortest,best_table = {last = start,
        cost_from_start = 0, cost_to_goal = estimate(start, goal, graph)
        }, {}

  best_table[node_to_id(start, graph)] = shortest

  local frontier, frontier_len, goal_id, max_number = {shortest}, 1, node_to_id(goal, graph), 32767.99

  while frontier_len > 0 do
    local cost, index_of_min = max_number
    for i = 1, frontier_len do
      local temp = frontier[i].cost_from_start + frontier[i].cost_to_goal
      if (temp <= cost) index_of_min,cost = i,temp
    end
    shortest = frontier[index_of_min]
    frontier[index_of_min], shortest.dead = frontier[frontier_len], true
    frontier_len -= 1
    local pth = shortest.last

    if node_to_id(pth, graph) == goal_id then
      pth = {goal}
      while shortest.prev do
        shortest = best_table[node_to_id(shortest.prev, graph)]
        add(pth, shortest.last,1)  --insert @ beginning of path
      end
      return pth
    end

    for n in all(neighbors(pth, graph)) do
      local id = node_to_id(n, graph)
      local old_best, new_cost_from_start =
      best_table[id],
      shortest.cost_from_start + 1

      if not old_best then
        old_best = {
          last = n,
          cost_from_start = max_number,
          cost_to_goal = estimate(n, goal, graph)
        }
        frontier_len += 1
        frontier[frontier_len], best_table[id] = old_best, old_best
      end

      if not old_best.dead and old_best.cost_from_start > new_cost_from_start then
        old_best.cost_from_start, old_best.prev = new_cost_from_start, pth
      end
    end
  end
end

function node_to_id(node)
  return node.y * 128 + node.x
end


-----
----- 18) load/save
-----

--lint: func::_init
function initpersist()
  cartdata("icegoat_picohaven2_08")
  saveversion=1
  dindx=0
end

--parallels dset() but with 2-byte values instead of 4-byte, allowing addr=0-127
-- if  addr not passed, instead increments global counter dindx, 
-- to set the "next" 2-byte address since the last call
--NOTE: different param order than dset!
function dset2(val,addr)
  dindx=addr or dindx
  poke2(0x5e00+2*dindx,val)
  dindx+=1
end

--similar to dset2() above, either passed address to read, or reads
-- next address beyong previously-read address
function dget2(addr)
  dindx=addr or dindx
  dindx+=1
  return peek2(0x5dfe+2*dindx)  -- 0x5e00-2*(dindx-1)
end


--lint: wongame,lastlevelwon,camp_wins
--new version of load_game() in v0.8 and later of cart
-- now uses poke2/peek2 to address 128 savegame memory locations, each 2 bytes in size
-- see also wrapper dget2() which if called with no argument returns the next save value,
--  but if called with an argument reads from that 2-byte location (0-127)
function load_game()
--   note: removed this safety check to save tokens, at least for now...
--         since the "continue game" menu option that calls this should only exist
--         if there's a nonzero value stored in persistent memory 0
--  if (dget2(0)==0) return

  --NOTE: this assignment uses ~30 fewer tokens than calling dget2() for each variable one line at a time
  --      (even if it's a bit less readable)
  saveversion,camp_wins,camp_gold,camp_kills,camp_time,lastlevelwon,p_lvl,p.maxhp,p_xp,p_gp,wongame,difficulty,mindifficulty=peek2(0x5e00,13)
  --load player action cards (12 items: # + 11 cards)
  pdeck={}
  --addr passed to dget2(#) is where in the savegame memory the "# of player cards" is stored, 
  -- and also sets dindx so that the dget2() calls without addresses just read the next values from there
  --this address leaves several unused savegame entries after the individual variables above, for future use without
  -- shifting the address of all the later items
  for _i=1,dget2(20) do 
    add(pdeck,pdeckmaster[dget2()])
  end
  --player mod cards
  --load list of mod upgrades applied in past
  -- then apply one by one as if leveling up
  for i=1,dget2(32) do
    addmodupgrade(i+1)
    upgrademod(pmodupgradesmaster[dget2()])
  end
  --items
  pitems={}
  for _i=1,dget2(41) do
    local item=storemaster[dget2()]
    add(pitems,item)
    del(store,item)
  end
  --which levels are unlocked?
  for i=1,dget2(50) do
    -- 1 vs 0 = unlocked or not unlocked
    lvls[i].unlocked=dget2()
    --lvls[i].unlocked=1  --TEMP DEBUG: force all levels unlocked!
    --lvls[i].chestcleared=dgetn()==1  --past experiment to have chests be "persistently collected"
  end
end

--lint: lastlevelwon,camp_wins
function save_game()
  poke2(0x5e00,saveversion,camp_wins,camp_gold,camp_kills,camp_time,lastlevelwon,p_lvl,p.maxhp,p_xp,p_gp,wongame,difficulty,mindifficulty)
  --player action cards (12 items: the #items + 11 items)
  save_helper(20,pdeck,pdeckmaster)  
  --player mod cards -- save the list of deltas from original
  --9 elements: the # of upgrades (up to 8 for 8 levelups) + the list of upgrade #s
  save_helper(32,pmodupgradesdone,pmodupgradesmaster)
  --player equipment
  --9 elements: the # (up to 8 items) + the items
  save_helper(41,pitems,storemaster)
  --levels unlocked (# of levels noted)
  --23 elements: the # of levels and then one slot per 22 levels
  --   (could save more compactly in future by just saving a list of unlocked levels)
  dset2(#lvls,50)
  for lvl in all(lvls) do
    dset2(lvl.unlocked)
    --dsetn(lvl.chestcleared and 1 or 0)  --experiment with chests you can't collect a second time if you fail and replay level)
  end
end

--noticed common code, extracted it here to save tokens
function save_helper(indx,objtbl,mastertbl)
  dset2(#objtbl,indx)
  for x in all(objtbl) do
    dset2(indextable(mastertbl,x))
  end
end
 