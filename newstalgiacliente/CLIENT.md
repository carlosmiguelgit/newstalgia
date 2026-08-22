# newstalgiacliente - Documentação Técnica

> **FUNÇÃO DESTE ARQUIVO:** Este `.md` é vivo. **A cada alteração que for feita no cliente (C++ / Lua / OTUI / Build / Protocolo), este arquivo DEVE ser atualizado** com a informação correta. Ele é nutrido continuamente e serve como fonte única de verdade sobre o funcionamento do cliente WASM.

---

## 1. Visão Geral

`newstalgiacliente` é um fork de OTClient v8 / CrystalServer v4.0.4, compilado para **WebAssembly (WASM)** via **Emscripten + Ninja**. Roda no navegador com `pthreads + SharedArrayBuffer` e se conecta ao `crystalserver` (15.25) via proxy WebSocket->TCP (`serve_web.py`).

```
Browser (WASM) --WebSocket--> serve_web.py:8081 --TCP--> crystalserver:7172
                --HTTP GET--> serve_web.py:8000 (otclient.html/js/wasm/data)
```

- **Protocolo Tibia:** 15.25, `GameLoginPending` ativo.
- **Cliente:** `newstalgiacliente/engine` (C++20, OTML, Lua 5.1, OpenGL ES 3.0 / WebGL2)
- **Build:** `engine/build-emscripten-web` (`CMake + Ninja + vcpkg wasm32-emscripten-pthread`)

---

## 2. Estrutura de Pastas

```
newstalgiacliente/
├── engine/                     # C++ core OTClient
│   ├── src/client/             # Game, LocalPlayer, ProtocolGameParse, UIItem
│   ├── src/framework/          # DrawPool, Logger, Lua, UI, Graphics, Net
│   ├── browser/                # shell.html para Emscripten
│   ├── build-emscripten-web/   # Build WASM (gerado)
│   │   ├── bin/                # otclient.html/js/wasm/data (preload)
│   │   ├── src/libotclient_core.a
│   │   └── vcpkg_installed/
│   └── otclientrc.lua, config.ini
├── modules/                    # Lua + OTUI (empacotado no otclient.data)
│   ├── game_inventory/         # inventory.lua / inventory.otui
│   ├── gamelib/                # player.lua (InventorySlot*), items.lua
│   ├── modulelib/              # controller.lua, eventcontroller.lua
│   └── ...
├── data/                       # sprites, things 1525, styles, etc.
├── init.lua, config.ini
└── serve_web.py                # Servidor HTTP + proxy WS->TCP
```

---

## 3. Build WASM (Emscripten)

### Toolchain
- **Emscripten SDK:** `D:\emsdk` (`D:\emsdk\emsdk_env.ps1`)
- **vcpkg:** `D:\vcpkg` (triplet `wasm32-emscripten-pthread`)
- **Ninja + CMake 3.2x**

### Comandos
```powershell
& "D:\emsdk\emsdk_env.ps1"
ninja -C engine/build-emscripten-web otclient_core   # só lib estática
ninja -C engine/build-emscripten-web otclient         # link final + empacota modules/data no otclient.data
# Atalho sem workdir (precisa de shell correto):
# ninja -t targets   # lista: otclient, otclient_core, otclient.html
```

> **ATENÇÃO:** Alterar qualquer `modules/**/*.lua` ou `data/**` exige `ninja otclient`, não só `otclient_core`, pois `otclient.data` é gerado com `--preload-file=../../modules@modules`.

### Saída
```
engine/build-emscripten-web/bin/
├── otclient.html  ~7KB
├── otclient.js    ~700KB
├── otclient.wasm  ~12MB
└── otclient.data  ~240MB (tudo de data/ + modules/ + init.lua)
```

### Flags Emscripten Relevantes
```
-pthread -matomics -mbulk-memory -s ALLOW_MEMORY_GROWTH=0 -s INITIAL_MEMORY=1GB
-s USE_PTHREADS=1 -s PTHREAD_POOL_SIZE=navigator.hardwareConcurrency
-s WASM=1 -s PROXY_TO_PTHREAD -s OFFSCREENCANVAS_SUPPORT=1 -s FETCH=1
--preload-file=../../modules@modules --use-preload-cache
```

---

## 4. `serve_web.py` - Servidor Local

```powershell
python serve_web.py [porta_web=8000] [porta_ws=8081] [porta_tcp=7172]
```

- Serve `bin/` com headers `COOP:same-origin` + `COEP:require-corp` (exige SharedArrayBuffer).
- Proxy `ws://0.0.0.0:8081 -> tcp 127.0.0.1:7172`.
- Endpoint `POST /log` e `POST /log/` : recebe logs do cliente (JS fetch) e imprime no terminal como `  [client] ...` (linha 82-96). Usado para debug WASM.
- `Cache-Control: no-store` mas navegador cacheia WASM; após rebuild fazer **Ctrl+F5**.

---

## 5. Protocolo Jogo (15.25)

### Conexão
- `Game::loginWorld` -> `ProtocolGame::login` -> TCP (via proxy WS).
- `Game::processGameStart` -> `g_lua.callGlobalField("g_game","onGameStart")`.

### Inventory Opcodes (Server -> Client)
- `0x78 (AddInventoryItem)`: `uint8 slot + Item (getItem)` -> `game.cpp:322 g_game.processInventoryChange(slot,item)`
- `0x79 (RemoveInventoryItem)`: `uint8 slot` -> `ItemPtr()` nulo -> `processInventoryChange(slot,nullptr)`

```cpp
// protocolgameparse.cpp:1785 / 1791
void parseAddInventoryItem(msg){ slot=msg->getU8(); item=getItem(msg); g_game.processInventoryChange(slot,item); }
void parseRemoveInventoryItem(msg){ slot=msg->getU8(); g_game.processInventoryChange(slot,ItemPtr()); }

// game.cpp:322
void Game::processInventoryChange(uint8 slot, ItemPtr item){
  if(item) item->setPosition(Position(UINT16_MAX,slot,0));
  m_localPlayer->setInventoryItem(slot,item); // file: localplayer.cpp:458
}
```

- Server define `Slots_t` 1..11 (`Head=1 ... StoreInbox=11`), Client/Lua `InventorySlotHead=1 ... InventorySlotPurse=11` (player.lua:586). Enum alinhado.

### `LocalPlayer::setInventoryItem`
```cpp
// localplayer.cpp:458
void LocalPlayer::setInventoryItem(InventorySlot slot, ItemPtr item){
  if(slot>=LastInventorySlot) return;
  if(m_inventoryItems[slot]==item) return; // evita spam se igual
  oldItem = m_inventoryItems[slot];
  m_inventoryItems[slot]=item;
  // clockExpire handling
  callLuaFieldUnchecked("onInventoryChange", slot, item, oldItem); // bypass m_events cache poison
}
```
> **Aprendido:** `callLuaField` tem cache `m_events` que pode envenenar com `false` se checado antes do `connect`. `callLuaFieldUnchecked` evita.

---

## 6. Módulo Inventory (Lua)

```
modules/game_inventory/inventory.lua
  getSlotPanelBySlot[slot] -> (slotPanel, toggler)
  inventoryEvent(player,slot,item,oldItem) -> slotPanel.item:setItem(item)
  refreshInventory_panel() -> re-lê player:getInventoryItem(i) para todos slots
  controller onGameStart: registerEvents(LocalPlayer, {onInventoryChange=inventoryEvent}):execute()
  controller EventController:execute(nil) chama act() SEM args -> inventoryEvent(player=nil,slot=nil) deve tolerar nil!
```

- `UIItem < UIWidget` filho `id:item` dentro de `MainInventoryItem` (10-items.otui, inventory.otui).
- `ItemsDatabase.setTier(widget,item)` só mexe em `widget.tier`.
- `inventoryShrink` bloqueia `inventoryEvent` e `refreshInventory_panel`.

> **Pitfall real (2026-08-21):** `string.format("slot=%d", slot)` quebra quando `execute()` chama `inventoryEvent()` sem args (`slot=nil`). Usar `tostring(slot)` e `%s`.

### `UIItem` (C++)
```cpp
// uiitem.cpp:33 drawSelf só no FOREGROUND
if(m_itemVisible && m_item){ bindFrameBuffer(); m_item->draw(); releaseFrameBuffer(); }
// uiitem.cpp:140 setItem
void UIItem::setItem(ItemPtr item){ m_item=item; m_itemId=item? id:0; callLuaField("onItemChange"); repaint(); }
// uiwidget.cpp:2229 repaint
void UIWidget::repaint(){ g_drawPool.repaint(FOREGROUND); }
```

---

## 7. Render - DrawPool

- Pools: `MAP`, `FOREGROUND` (UI), `CREATURE_INFORMATION`, etc. `DrawPoolManager g_drawPool`.
- `FOREGROUND` tem `FrameBuffer` com cache por hash + timer FPS10 (100ms).

```cpp
// drawpool.h:36 DrawHashController
bool put(hash){ if(m_lastObjectHash!=hash){ hash_union(m_currentHash,hash); } }
void forceUpdate(){ m_currentHash=1; }
bool wasModified(){ return m_currentHash != m_lastHash; }
void reset(){ if(m_currentHash!=1) m_lastHash=m_currentHash; m_currentHash=0; ... }

// drawpool.h:99
void repaint(){ m_hashCtrl.forceUpdate(); m_refreshTimer.update(-1000); } // não seta m_shouldRepaint!

// drawpool.cpp:280
void DrawPool::release(){
  if(hasFrameBuffer() && !wasModified() && !canRefresh()){ clearObjs; return; } // SKIPA redraw
  m_refreshTimer.restart();
  // move objs -> m_objectsDraw[0]
  m_shouldRepaint.store(true);
}

// drawpoolmanager.cpp:219
void drawObjects(pool){
  if(!shouldRepaint && hasFramebuffer) return; // mantém framebuffer antigo
  if(hasFramebuffer) pool->m_framebuffer->bind();
  if(shouldRepaint) swap(m_objectsDraw[0],m_objectsDraw[1]);
  for(obj: m_objectsDraw[1]) drawObject();
  if(hasFramebuffer) pool->m_framebuffer->release();
}
void drawPool(type){ drawObjects(pool); if(hasFramebuffer) m_framebuffer->draw(); }
```

- `preDraw(FOREGROUND,f)` faz `resetState() -> reset()` , executa `f()` (UI desenha), `release()` (decide `shouldRepaint`), depois `draw()` chama `drawObjects`.
- `repaint()` via `forceUpdate()+update(-1000)` deveria forçar `wasModified` ou `canRefresh`, mas **não seta `m_shouldRepaint` diretamente** - depende do hash mudar no próximo frame.

> **Debug 2026-08-21:** Sprite do inventory persistia mesmo com `m_item=nullptr` porque hash/timer não forçavam redraw. Tentativas com `callLuaFieldUnchecked`, `UIItem::setItem` + `repaint`, `setWidth` hack falharam. Solução correta exige garantir `wasModified` ou `canRefresh` verdadeiro.

---

## 8. Lua <-> C++ Bridge

- `push_luavalue(shared_ptr<T> where T:LuaObject)`: se `obj==nullptr` -> `g_lua.pushNil()` (luavaluecasts.h:316)
- `luavalue_cast(shared_ptr<T>&)`: `isNil -> obj=nullptr -> ptr=nullptr` (luavaluecasts.cpp:365)
- `LuaObject::luaCallLuaField`: `pushObject(self) -> getField(field) -> if !isNil -> insert(self) -> polymorphicPush(args) -> signalCall` (luaobject.h:168)
- `signalCall`: se `isFunction` -> `safeCall`; se `isTable` (vários handlers) itera; se `isNil` ignora.

---

## 9. Logger (WASM)

```cpp
Logger g_logger; // framework/core/logger.h/.cpp
void log(level,msg){ spdlog + m_onLog callback via g_dispatcher }
g_logger.setOnLog(cb) // cb(level,msg,when) -> em browser faz fetch POST /log
```

- Nível default `LogDebug`; `NDEBUG` filtra `LogFine/LogDebug`.
- No browser, `m_onLog` é setado para `fetch("/log", {method:"POST", body:msg})` -> `serve_web.py:82 do_POST` imprime `  [client] ...` no terminal Python.
- Lua `print()` e `g_logger.info(fmt)` caem no mesmo `/log`.

---

## 10. Bugs & Aprendizados Registrados

| Data | Bug | Causa | Fix |
|------|-----|-------|-----|
| 2026-08-21 | Inventory sprite fica após desequipar, só sai no relog | `DrawPool::repaint()` não seta `m_shouldRepaint` + `release()` skip quando hash igual | Em investigação - `forceUpdate`+timer deve bastar mas não bastou; tentativa `setWidth` hack falhou |
| 2026-08-21 | `inventory.lua:118 format %d nil` quebrou todo inventory | `EventController:execute()` chama `act()` sem args | Trocar `%d` -> `%s` + `tostring(slot)` |
| 2026-08-21 | Build `bin/` não atualizava logs | `ninja otclient_core` só lib, não relinka `otclient.wasm` | Usar `ninja otclient` para link + pack `otclient.data` |
| Previo | `callLuaField` cache poison | `m_events[field]=false` se checado antes do `connect` | Usar `callLuaFieldUnchecked` em `localplayer.cpp:478` |

---

## 11. Como Contribuir / Checklist de Alteração

1. **Edite C++ ou Lua.**
2. **Atualize este `CLIENT.md`** na seção correspondente (Protocolo / DrawPool / Inventory / Build).
3. **Compile WASM:** `& "D:\emsdk\emsdk_env.ps1"; ninja -C engine/build-emscripten-web otclient`
4. **Teste:** `python serve_web.py` + `Ctrl+F5` no navegador.
5. **Logs:** use `g_logger.info("...")` (C++) ou `print()`/`g_logger.info()` (Lua) -> aparecem em `POST /log` no terminal.
6. **Commit:** `git status`, `git diff`, mensagem concisa.

---

## 12. Referências de Código

- `engine/src/client/localplayer.cpp:458` - `setInventoryItem`
- `engine/src/client/game.cpp:322` - `processInventoryChange`
- `engine/src/client/protocolgameparse.cpp:1791` - `parseRemoveInventoryItem`
- `engine/src/client/uiitem.cpp:33` - `UIItem::drawSelf`
- `engine/src/client/uiitem.cpp:140` - `UIItem::setItem`
- `engine/src/framework/graphics/drawpool.h:36,99` - `DrawHashController`, `repaint`
- `engine/src/framework/graphics/drawpool.cpp:280` - `release` early-return
- `engine/src/framework/graphics/drawpoolmanager.cpp:219` - `drawObjects`
- `engine/src/framework/luaengine/luavaluecasts.h:316` - `push nil`
- `engine/src/framework/luaengine/luaobject.h:168,237` - `luaCallLuaField`, `callLuaFieldUnchecked`
- `modules/game_inventory/inventory.lua:117,292` - `inventoryEvent`, `onGameStart`
- `modules/modulelib/eventcontroller.lua:66` - `execute`
- `engine/src/framework/core/logger.cpp:134,186` - `log`, `m_onLog`
- `serve_web.py:82` - `POST /log` -> terminal

---

## 13. xBRZ - Removido em 2026-08-21

Filtro xBRZ (`engine/src/framework/graphics/xbrz/`, `thingtype.h:sourceXbrz`, `gameconfig.h:m_hdGraphics`, `luafunctions.cpp` binds, `data_options.lua:hdGraphics` + `graphics.otui:hdGraphics`) **removido completamente** a pedido do usuário (gerava granulado/chiado). Código limpo via `git checkout` + `Remove-Item xbrz/`. Build volta ao original. Re-ativação futura deve usar `exemplo/surfaceSoftware.cpp:753` como referência (`xbrz::scale(2, 32,32, ARGB)` por sprite).

---
*Última nutrição: 2026-08-21 - Remoção completa xBRZ, limpeza código.*
