#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
import json
import math
import time
import random
import subprocess

try:
    from PySide6 import QtCore, QtGui, QtWidgets
    QT_LIB = "PySide6"
except ImportError:
    try:
        from PyQt5 import QtCore, QtGui, QtWidgets
        QT_LIB = "PyQt5"
    except ImportError:
        print("Please install PySide6 or PyQt5 to run this overlay: pip install PySide6")
        sys.exit(1)

def get_locale_language():
    try:
        for var in ["LANG", "LC_ALL", "LC_CTYPE"]:
            val = os.environ.get(var)
            if val and val.lower().startswith("ko"):
                return "ko"
        import locale
        lang, _ = locale.getlocale()
        if lang and lang.lower().startswith("ko"):
            return "ko"
        lang, _ = locale.getdefaultlocale()
        if lang and lang.lower().startswith("ko"):
            return "ko"
    except Exception:
        pass
    return "en"

IS_KOREAN = get_locale_language() == "ko"

TRANSLATIONS = {
    "ko": {
        "prework": "시작전",
        "working": "작업중",
        "done": "완료(실패)",
        "expired": "실패 (만료)",
        "approval": "허가 대기",
        "input": "입력 대기",
        "ended": "종료",
        "completed": "완료"
    },
    "en": {
        "prework": "Ready",
        "working": "Working",
        "done": "Done",
        "expired": "Fainted (Expired)",
        "approval": "Approval Needed",
        "input": "Input Needed",
        "ended": "Ended",
        "completed": "Completed"
    }
}

def translate(key):
    lang = "ko" if IS_KOREAN else "en"
    return TRANSLATIONS[lang].get(key, key)

# Default configuration values
DEFAULTS = {
    "workingCpuThreshold": 12.0,
    "workingCpuExitThreshold": 6.0,
    "petMinSize": 8.0,
    "petMaxSize": 28.0,
    "overlayBandHeight": 440.0,
    "fpsActive": 60.0,
    "fpsIdle": 60.0,
    "fpsQuiet": 12.0,
    "pollIntervalSeconds": 2.5,
    "preworkAreaRatio": 0.46,
    "workingAreaRatio": 0.46,
    "clickNameplateOnly": True,
    "showStateRail": True,
    "showShellTabs": False,
    "petDraggingEnabled": True,
    "dragPetBodyEnabled": True,
    "soundEffectsEnabled": True,
    "soundEffectsVolume": 0.34,
    "soundEffectsCooldownSeconds": 0.08,
    "dragStartSoundName": "Pop",
    "dragDropSoundName": "Tink",
    "focusSoundName": "Glass",
    "completionSoundName": "Hero",
    "completionVoiceEnabled": True,
    "completionVoicePath": "",
    "completionVoiceVolume": 0.58,
    "completionVoiceCooldownSeconds": 1.2,
    "excludedTitleContains": [],
    "monitorMode": "auto"
}

class OverlayConfig:
    def __init__(self):
        self.__dict__.update(DEFAULTS)
        self.load()

    def load(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        path = os.path.join(root, "config.json")
        if not os.path.exists(path):
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for k, v in DEFAULTS.items():
                if k in data:
                    val = data[k]
                    if k in ["workingCpuThreshold", "workingCpuExitThreshold", "petMinSize", "petMaxSize", "overlayBandHeight", "fpsActive", "fpsIdle", "fpsQuiet", "pollIntervalSeconds", "preworkAreaRatio", "workingAreaRatio", "soundEffectsVolume", "soundEffectsCooldownSeconds", "completionVoiceVolume", "completionVoiceCooldownSeconds"]:
                        try:
                            val = float(val)
                        except (ValueError, TypeError):
                            val = v
                    self.__dict__[k] = val
        except Exception as e:
            print(f"Error loading config.json: {e}")

class PetInfo:
    def __init__(self, key):
        self.key = key
        self.title = ""
        self.provider = "shell"
        self.pane_ref = ""
        self.workspace_ref = ""
        self.window_ref = ""
        self.cpu = 0.0
        self.memory_bytes = 0
        self.focused = False
        self.process_names = []
        self.token_expired = False
        self.status = "active"
        self.context_percentage = -1
        self.context_text = ""
        
        self.size = 16.0
        self.position = QtCore.QPointF(200.0, 50.0)
        self.velocity = QtCore.QPointF(0.0, 0.0)
        self.home_x = 200.0
        self.home_y = 50.0
        self.lane_width = 100.0
        self.slot_index = 0
        self.state = "prework"
        self.facing = 1.0
        
        self.bob_phase = random.uniform(0, 10)
        self.alerting = False
        self.alert_until = 0.0
        self.last_active_at = time.time()
        self.manually_placed = False
        self.ended_at = 0.0
        self.next_turn_at = 0.0

class CmuxStateReader:
    def __init__(self):
        pass

    def parse_percentage_from_string(self, string):
        if not string:
            return -1
        import re
        match = re.search(r'(\d+)\s*%', string)
        if match:
            return int(match.group(1))
        dec_match = re.search(r'\b(0\.\d+)\b', string)
        if dec_match:
            return int(float(dec_match.group(1)) * 100.0)
        cleaned = string.strip()
        if cleaned.isdigit():
            val = int(cleaned)
            if 0 <= val <= 100:
                return val
        return -1

    def extract_context_info_for_session(self, info, workspace_contexts, workspace_names):
        pct = -1
        text = None
        ws_ref = info.get("workspace_ref", "")
        
        # 1. Try workspace tag first
        tag_val = workspace_contexts.get(ws_ref, "")
        if tag_val:
            pct = self.parse_percentage_from_string(tag_val)
            text = tag_val
            
        # 2. Try workspace title
        ws_name = workspace_names.get(ws_ref, "")
        if pct == -1 and ws_name:
            pct = self.parse_percentage_from_string(ws_name)
            if pct >= 0:
                text = f"{pct}%"
                
        # 3. Try surface title
        tab_name = info.get("title", "")
        if pct == -1 and tab_name:
            pct = self.parse_percentage_from_string(tab_name)
            if pct >= 0:
                text = f"{pct}%"
                
        # 4. If Codex, read latest rollout log file
        if pct == -1 and info.get("provider") == "codex":
            import os, glob
            profile_dir = ""
            key_lower = info.get("key", "").lower()
            if "sol" in key_lower:
                profile_dir = os.path.expanduser("~/.codex-sol")
            elif "et" in key_lower:
                profile_dir = os.path.expanduser("~/.codex-et")
            else:
                profile_dir = os.path.expanduser("~/.codex")
                
            sessions_dir = os.path.join(profile_dir, "sessions")
            # Find latest jsonl
            try:
                list_files = glob.glob(os.path.join(sessions_dir, "**", "rollout-*.jsonl"), recursive=True)
                if list_files:
                    latest_log = max(list_files, key=os.path.getmtime)
                    if os.path.exists(latest_log):
                        # Read last 35 lines
                        with open(latest_log, "r", encoding="utf-8", errors="ignore") as f:
                            lines = f.readlines()[-35:]
                        tail_content = "".join(lines)
                        
                        import re
                        match = re.search(r'"total_tokens":\s*(\d+)[^}]*"model_context_window":\s*(\d+)', tail_content)
                        if match:
                            total_tokens = int(match.group(1))
                            window = int(match.group(2))
                            if window > 0:
                                pct = int((total_tokens * 100) / window)
                                tokens_k = f"{total_tokens / 1000.0:.0f}k"
                                window_k = f"{window / 1000.0:.0f}k"
                                text = f"{pct}% ({tokens_k}/{window_k})"
            except Exception:
                pass
                
        # 5. Try cmux read-screen
        if text is None and info.get("key") and info.get("provider") != "shell":
            screen_cmd = f"cmux read-screen --surface {info.get('key')} --lines 40 2>/dev/null"
            screen_content = self.run_shell(screen_cmd)
            if screen_content:
                import re
                # Search for token counts: e.g. "367.3k tokens"
                token_match = re.search(r'([\d,]+(?:\.\d+)?[kM]?)\s*(?:tokens|t\b)', screen_content, re.IGNORECASE)
                if token_match:
                    text = f"{token_match.group(1)} t"
                    
                # Check for explicit "X / Y" or "X of Y"
                fraction_match = re.search(r'([\d,]+(?:\.\d+)?[kM]?)\s*(?:/|of)\s*([\d,]+(?:\.\d+)?[kM]?)', screen_content, re.IGNORECASE)
                if fraction_match:
                    used_str = fraction_match.group(1)
                    limit_str = fraction_match.group(2)
                    text = f"{used_str}/{limit_str} t"
                    
                    # Try to parse
                    try:
                        def parse_val(s):
                            s = s.lower()
                            if s.endswith("k"):
                                return float(s[:-1]) * 1000.0
                            elif s.endswith("m"):
                                return float(s[:-1]) * 1000000.0
                            return float(s.replace(",", ""))
                        used = parse_val(used_str)
                        limit = parse_val(limit_str)
                        if limit > 0:
                            pct = int((used * 100) / limit)
                            text = f"{pct}% ({used_str}/{limit_str})"
                    except Exception:
                        pass
                        
                # Fallback to screen percentage
                if pct == -1:
                    pct_match = re.search(r'(\d+)\s*%', screen_content)
                    if pct_match:
                        pct = int(pct_match.group(1))
                        text = f"{pct}%"
                        
        info["context_percentage"] = pct
        info["context_text"] = text

    def run_shell(self, cmd):
        try:
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return res.stdout
        except Exception:
            return ""

    def read_focused_refs(self):
        output = self.run_shell("CMUX_QUIET=1 cmux identify --no-caller")
        if not output:
            return {}
        try:
            data = json.loads(output)
            return data.get("focused", {})
        except Exception:
            return {}

    def read_local_system_sessions(self):
        sessions = []
        processes = {}
        shells = []
        
        if sys.platform == "win32":
            try:
                cmd = 'powershell -NoProfile -Command "Get-Process | Select-Object Id, ParentProcessId, CPU, WorkingSet, Name | ConvertTo-Json"'
                res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    data = json.loads(res.stdout)
                    if isinstance(data, dict):
                        data = [data]
                    for proc in data:
                        pid = proc.get("Id")
                        ppid = proc.get("ParentProcessId")
                        cpu = proc.get("CPU") or 0.0
                        rss = proc.get("WorkingSet") or 0
                        comm = proc.get("Name") or ""
                        if pid is not None:
                            processes[pid] = {
                                "pid": pid,
                                "ppid": ppid,
                                "cpu": cpu,
                                "rss": rss,
                                "comm": comm
                            }
                            lower_comm = comm.lower()
                            if lower_comm in ["cmd", "powershell", "pwsh", "bash"]:
                                shells.append(processes[pid])
            except Exception as e:
                print(f"Error reading Windows processes: {e}")
        else:
            try:
                cmd = "ps -cx -u $(id -u) -o pid,ppid,%cpu,rss,comm 2>/dev/null"
                res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
                lines = res.stdout.splitlines()
                for line in lines:
                    trimmed = line.strip()
                    if not trimmed or trimmed.startswith("PID"):
                        continue
                    parts = trimmed.split()
                    if len(parts) >= 5:
                        try:
                            pid = int(parts[0])
                            ppid = int(parts[1])
                            cpu = float(parts[2])
                            rss = int(parts[3]) * 1024
                            comm = " ".join(parts[4:])
                            processes[pid] = {
                                "pid": pid,
                                "ppid": ppid,
                                "cpu": cpu,
                                "rss": rss,
                                "comm": comm
                            }
                            if comm in ["zsh", "bash", "sh", "fish"]:
                                shells.append(processes[pid])
                        except ValueError:
                            continue
            except Exception as e:
                print(f"Error reading Unix processes: {e}")

        def collect_descendants(parent_pid, arr):
            for p in processes.values():
                if p["ppid"] == parent_pid:
                    arr.append(p)
                    collect_descendants(p["pid"], arr)

        for shell in shells:
            descendants = []
            collect_descendants(shell["pid"], descendants)
            
            total_cpu = shell["cpu"]
            total_rss = shell["rss"]
            active_comm = shell["comm"]
            max_child_cpu = -1.0
            
            for child in descendants:
                total_cpu += child["cpu"]
                total_rss += child["rss"]
                if child["cpu"] > max_child_cpu:
                    max_child_cpu = child["cpu"]
                    active_comm = child["comm"]
                elif max_child_cpu <= 0.0 and active_comm == shell["comm"]:
                    active_comm = child["comm"]

            # Determine provider dynamically
            provider = "shell"
            lower_shell_comm = shell["comm"].lower()
            if "codex" in lower_shell_comm:
                provider = "codex"
            elif "claude" in lower_shell_comm:
                provider = "claude"
            elif "agy" in lower_shell_comm or "gemini" in lower_shell_comm:
                provider = "agy"
                
            for child in descendants:
                c_name = child["comm"].lower()
                if "codex" in c_name:
                    provider = "codex"
                    break
                elif "claude" in c_name or "클로드" in c_name:
                    provider = "claude"
                    break
                elif "agy" in c_name or "gemini" in c_name:
                    provider = "agy"
                    break

            key = f"shell:{shell['pid']}"
            info = {
                "key": key,
                "surface_ref": key,
                "pane_ref": key,
                "workspace_ref": key,
                "window_ref": key,
                "title": active_comm,
                "provider": provider,
                "status": "active",
                "cpu": total_cpu,
                "memory_bytes": total_rss,
                "process_count": len(descendants),
                "focused": False,
                "token_expired": False,
                "last_notification": "",
                "last_notification_unread": False,
                "context_percentage": -1,
                "context_text": None
            }
            self.extract_context_info_for_session(info, {}, {})
            sessions.append(info)
            
        return sessions

    def read_sessions(self, config=None):
        mode = "auto"
        if config:
            mode = getattr(config, "monitorMode", "auto")
            
        use_cmux = mode == "cmux"
        if mode == "auto":
            if sys.platform == "win32":
                test = self.run_shell("where cmux")
            else:
                test = self.run_shell("which cmux")
            use_cmux = len(test.strip()) > 0
            
        if not use_cmux:
            return self.read_local_system_sessions()

        output = self.run_shell("cmux top --all --processes --format tsv")
        focused = self.read_focused_refs()
        focused_surface = focused.get("surface_ref", "")
        focused_pane = focused.get("pane_ref", "")
        
        notif_out = self.run_shell("cmux list-notifications")
        latest_notif = {}
        for line in notif_out.splitlines():
            if not line or line.startswith("Error:"):
                continue
            parts = line.split("|")
            if len(parts) < 7:
                continue
            ws_name = next((col[4:] for col in parts if col.startswith("pct:")), parts[4])
            is_unread = parts[3] != "read"
            body = parts[6]
            if ws_name and body:
                if ws_name not in latest_notif:
                    latest_notif[ws_name] = (body, is_unread)

        sessions = []
        workspace_to_window = {}
        pane_to_workspace = {}
        workspace_names = {}
        workspace_contexts = {}
        
        for line in output.splitlines():
            if not line:
                continue
            cols = line.split("\t")
            if len(cols) < 7:
                continue
            t, ident, parent, title = cols[3], cols[4], cols[5], cols[6]
            if t == "workspace" and ident.startswith("workspace:"):
                workspace_to_window[ident] = parent or ""
                workspace_names[ident] = title or ""
            elif t == "pane" and ident.startswith("pane:"):
                pane_to_workspace[ident] = parent or ""
            elif t == "tag":
                if ":tag:context" in ident or ":tag:progress" in ident or ":tag:token" in ident:
                    if parent and title:
                        workspace_contexts[parent] = title
            elif t == "surface" and ident.startswith("surface:"):
                s_ref = ident
                p_ref = parent or ""
                w_ref = pane_to_workspace.get(p_ref, "")
                window_ref = workspace_to_window.get(w_ref, "")
                ws_name = workspace_names.get(w_ref, "")
                
                tab_name = title.strip()
                prefix_chars = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏✳✱*·• "
                while tab_name and (tab_name[0] in prefix_chars or 0x2800 <= ord(tab_name[0]) <= 0x28FF):
                    tab_name = tab_name[1:].strip()
                if "/" in tab_name:
                    tab_name = tab_name.replace("…", "").split("/")[-1]
                if not tab_name:
                    tab_name = s_ref
                
                lower_name = tab_name.lower()
                provider = "shell"
                if "codex" in lower_name:
                    provider = "codex"
                elif "claude" in lower_name or "클로드" in lower_name:
                    provider = "claude"
                elif "agy" in lower_name or "gemini" in lower_name:
                    provider = "agy"
                
                cpu = float(cols[0]) if cols[0] else 0.0
                mem = int(cols[1]) if cols[1] else 0
                focused_bool = (focused_surface and s_ref == focused_surface) or (focused_pane and p_ref == focused_pane)
                
                notif_body, notif_unread = latest_notif.get(w_ref, ("", False))
                
                info = {
                    "key": s_ref,
                    "surface_ref": s_ref,
                    "pane_ref": p_ref,
                    "workspace_ref": w_ref,
                    "window_ref": window_ref,
                    "title": tab_name,
                    "provider": provider,
                    "cpu": cpu,
                    "memory_bytes": mem,
                    "focused": focused_bool,
                    "last_notification": notif_body,
                    "last_notification_unread": notif_unread,
                    "token_expired": "token expired" in notif_body.lower(),
                    "context_percentage": -1,
                    "context_text": None
                }
                self.extract_context_info_for_session(info, workspace_contexts, workspace_names)
                sessions.append(info)
        return sessions

class OverlayWindow(QtWidgets.QWidget):
    def __init__(self, screen_index=0):
        super().__init__()
        self.screen_index = screen_index
        self.config = OverlayConfig()
        self.reader = CmuxStateReader()
        self.pets = {}
        self.last_sound_effect_at = 0.0
        self.last_poll_time = 0.0
        self.last_poll_interval = self.config.pollIntervalSeconds
        self.paused = False
        
        self.setWindowFlags(
            QtCore.Qt.WindowType.FramelessWindowHint |
            QtCore.Qt.WindowType.WindowStaysOnTopHint |
            QtCore.Qt.WindowType.SubWindow
        )
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_NoSystemBackground, True)
        
        self.load_sprites()
        self.update_geometry()
        
        self.pressed_pet = None
        self.press_point = QtCore.QPoint()
        self.press_pet_pos = QtCore.QPointF()
        self.dragging_pet = False
        
        self.fps = self.config.fpsActive
        self.animation_timer = QtCore.QTimer()
        self.animation_timer.timeout.connect(self.step)
        self.animation_timer.start(int(1000.0 / self.fps))
        
        self.poll()

    def load_sprites(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        asset_path = os.path.join(root, "assets", "mochi", "mochi-front-animated.gif")
        
        self.sprite_frames = []
        if os.path.exists(asset_path):
            reader = QtGui.QImageReader(asset_path)
            while True:
                img = reader.read()
                if img.isNull():
                    break
                self.sprite_frames.append(QtGui.QPixmap.fromImage(img))
                if not reader.jumpToNextImage():
                    break
        
        if not self.sprite_frames:
            fallback_img = os.path.join(root, "assets", "mochi", "mochi-front.png")
            if os.path.exists(fallback_img):
                self.sprite_frames.append(QtGui.QPixmap(fallback_img))
            else:
                pix = QtGui.QPixmap(32, 32)
                pix.fill(QtGui.QColor(255, 180, 200))
                self.sprite_frames.append(pix)

    def update_geometry(self):
        screens = QtWidgets.QApplication.screens()
        if not screens:
            return
        screen = screens[min(self.screen_index, len(screens) - 1)]
        geom = screen.availableGeometry()
        h = int(self.config.overlayBandHeight)
        self.setGeometry(geom.x(), geom.y() + geom.height() - h, geom.width(), h)

    def desired_fps(self):
        if not self.pets:
            return self.config.fpsQuiet
        has_activity = any(p.cpu > 0.08 or p.alerting or p.focused for p in self.pets.values())
        return self.config.fpsActive if has_activity else self.config.fpsIdle

    def step(self):
        if self.paused:
            return
        now = time.time()
        
        if now - self.last_poll_time > self.config.pollIntervalSeconds:
            self.poll()
            
        target_fps = self.desired_fps()
        if abs(self.fps - target_fps) > 0.5:
            self.fps = target_fps
            self.animation_timer.setInterval(int(1000.0 / self.fps))
            
        dt = 1.0 / self.fps
        pets_list = list(self.pets.values())
        
        for pet in pets_list:
            if pet.token_expired:
                pet.velocity = QtCore.QPointF(0, 0)
                pet.next_turn_at = now + 9999.0
                rx = pet.home_x - pet.position.x()
                ry = pet.home_y - pet.position.y()
                if abs(rx) > 2.0 or abs(ry) > 2.0:
                    pet.position = QtCore.QPointF(pet.position.x() + rx * 0.10, pet.position.y() + ry * 0.10)
            elif now >= pet.next_turn_at:
                pull_x = max(-0.15, min(0.15, (pet.home_x - pet.position.x()) * 0.0015))
                pull_y = max(-0.10, min(0.10, (pet.home_y - pet.position.y()) * 0.0020))
                pet.velocity = QtCore.QPointF(
                    random.uniform(-0.58, 0.58) + pull_x,
                    random.uniform(-0.42, 0.42) + pull_y
                )
                pet.next_turn_at = now + random.uniform(1.5, 4.0)

            if not pet.token_expired:
                dist_x = pet.home_x - pet.position.x()
                dist_y = pet.home_y - pet.position.y()
                pull_x = max(-0.15, min(0.15, dist_x * 0.0015)) if abs(dist_x) > 120.0 else 0.0
                pull_y = max(-0.12, min(0.12, dist_y * 0.0025)) if abs(dist_y) > 60.0 else 0.0
                
                avoid_x, avoid_y = 0.0, 0.0
                for other in pets_list:
                    if other == pet or other.status == "ended":
                        continue
                    dx = pet.position.x() - other.position.x()
                    dy = pet.position.y() - other.position.y()
                    limit_x, limit_y = 84.0, 40.0
                    if abs(dx) < limit_x and abs(dy) < limit_y:
                        fx = (limit_x - abs(dx)) / limit_x
                        fy = (limit_y - abs(dy)) / limit_y
                        dir_x = 1.0 if dx >= 0 else -1.0
                        dir_y = 1.0 if dy >= 0 else -1.0
                        if abs(dy) < 0.01:
                            dir_y = 1.0 if pet.slot_index % 2 == 0 else -1.0
                        avoid_x += dir_x * fx * 0.16
                        avoid_y += dir_y * fy * 0.10
                
                pet.velocity = QtCore.QPointF(
                    max(-1.5, min(1.5, pet.velocity.x() * 0.992 + pull_x + avoid_x)),
                    max(-1.1, min(1.1, pet.velocity.y() * 0.988 + pull_y + avoid_y))
                )
                
                speed_scale = max(0.5, min(2.2, 16.0 / max(1.0, pet.size)))
                pet.position = QtCore.QPointF(
                    pet.position.x() + pet.velocity.x() * dt * 90.0 * speed_scale,
                    pet.position.y() + pet.velocity.y() * dt * 90.0 * speed_scale
                )
                
                if abs(pet.velocity.x()) > 0.01:
                    pet.facing = 1.0 if pet.velocity.x() >= 0 else -1.0
                pet.bob_phase += dt * (5.5 + math.hypot(pet.velocity.x(), pet.velocity.y()) * 5.0) * speed_scale

            walk_area = self.walk_area_for_pet(pet)
            base_area = self.walk_area_for_pet_size(pet.size)
            if pet.position.x() < walk_area.left() or pet.position.x() > walk_area.right():
                dir_x = 1.0 if pet.home_x >= pet.position.x() else -1.0
                pet.velocity = QtCore.QPointF(
                    max(-0.85, min(0.85, pet.velocity.x() * 0.70 + dir_x * 0.34)),
                    pet.velocity.y()
                )
                pet.position = QtCore.QPointF(
                    max(base_area.left(), min(base_area.right(), pet.position.x())),
                    pet.position.y()
                )
            if pet.position.y() < walk_area.top() or pet.position.y() > walk_area.bottom():
                pet.velocity = QtCore.QPointF(pet.velocity.x(), -pet.velocity.y())
                pet.position = QtCore.QPointF(
                    pet.position.x(),
                    max(walk_area.top(), min(walk_area.bottom(), pet.position.y()))
                )

        self.separate_overlapping_pets()
        self.update()
        self.update_mask()

    def update_mask(self):
        region = QtGui.QRegion()
        for pet in self.pets.values():
            s_rect = self.sprite_rect_for_pet(pet).toRect()
            n_rect = self.nameplate_rect_for_pet(pet).toRect()
            region = region.united(QtGui.QRegion(s_rect.adjusted(-2, -2, 2, 2)))
            region = region.united(QtGui.QRegion(n_rect.adjusted(-2, -2, 2, 2)))
        self.setMask(region)

    def separate_overlapping_pets(self):
        pets = [p for p in self.pets.values() if p.status != "ended"]
        if len(pets) < 2:
            return
            
        for pass_idx in range(4):
            for i in range(len(pets)):
                a = pets[i]
                for j in range(i + 1, len(pets)):
                    b = pets[j]
                    dx = b.position.x() - a.position.x()
                    dy = b.position.y() - a.position.y()
                    
                    min_x = max(64.0, (a.size + b.size) * 1.55)
                    min_y = max(36.0, (a.size + b.size) * 0.78)
                    
                    if abs(dx) < min_x and abs(dy) < min_y:
                        dir_x = 1.0 if dx >= 0 else -1.0
                        push_x = (min_x - abs(dx)) * 0.18 + 0.2
                        a.position = QtCore.QPointF(a.position.x() - dir_x * push_x, a.position.y())
                        b.position = QtCore.QPointF(b.position.x() + dir_x * push_x, b.position.y())
                        
                        if abs(dy) < min_y:
                            dir_y = 1.0 if dy >= 0 else -1.0
                            if abs(dy) < 0.01:
                                dir_y = 1.0 if random.random() >= 0.5 else -1.0
                            push_y = (min_y - abs(dy)) * 0.10 + 0.1
                            a.position = QtCore.QPointF(a.position.x(), a.position.y() - dir_y * push_y)
                            b.position = QtCore.QPointF(b.position.x(), b.position.y() + dir_y * push_y)
                        
                        a.velocity = QtCore.QPointF(a.velocity.x() * 0.40, a.velocity.y() * 0.40)
                        b.velocity = QtCore.QPointF(b.velocity.x() * 0.40, b.velocity.y() * 0.40)
                        
        for pet in pets:
            walk_area = self.walk_area_for_pet(pet)
            pet.position = QtCore.QPointF(
                max(walk_area.left(), min(walk_area.right(), pet.position.x())),
                max(walk_area.top(), min(walk_area.bottom(), pet.position.y()))
            )

    def walk_area_for_pet_size(self, size):
        w = self.width()
        h = self.height()
        top = h - 38.0 - size * 0.5
        bottom = h - 28.0
        return QtCore.QRectF(10.0, top, w - 20.0, max(2.0, bottom - top))

    def walk_area_for_pet(self, pet):
        return self.walk_area_for_pet_size(pet.size)

    def sprite_rect_for_pet(self, pet):
        scale = pet.size / 40.0
        w = 40.0 * scale
        h = 40.0 * scale
        x = pet.position.x() - w / 2.0
        y = pet.position.y() - h
        return QtCore.QRectF(x, y, w, h)

    def nameplate_rect_for_pet(self, pet):
        sprite_rect = self.sprite_rect_for_pet(pet)
        label = pet.title or pet.provider or "cmux"
        w = max(64.0, len(label) * 6.5 + 14.0)
        h = 24.0
        status_text = getattr(pet, "status_text", "")
        if status_text:
            w = max(w, len(status_text) * 6.5 + 14.0)
            h = 36.0
        x = pet.position.x() - w / 2.0
        y = sprite_rect.bottom() + 4.0
        return QtCore.QRectF(x, y, w, h)

    def pet_at_point(self, point):
        for pet in self.pets.values():
            s_rect = self.sprite_rect_for_pet(pet)
            n_rect = self.nameplate_rect_for_pet(pet)
            if s_rect.contains(point) or n_rect.contains(point):
                return pet
        return None

    def mousePressEvent(self, event):
        pos = event.position() if hasattr(event, "position") else event.pos()
        pet = self.pet_at_point(pos)
        if not pet:
            return
            
        if event.button() == QtCore.Qt.MouseButton.RightButton:
            QtWidgets.QApplication.quit()
            return
            
        if self.config.petDraggingEnabled:
            self.pressed_pet = pet
            self.press_point = pos
            self.press_pet_pos = pet.position
            self.dragging_pet = False

    def mouseMoveEvent(self, event):
        if not self.pressed_pet or not self.config.petDraggingEnabled:
            return
        pos = event.position() if hasattr(event, "position") else event.pos()
        dx = pos.x() - self.press_point.x()
        dy = pos.y() - self.press_point.y()
        
        if not self.dragging_pet and (dx*dx + dy*dy) < 16.0:
            return
            
        self.dragging_pet = True
        pet = self.pressed_pet
        proposed = QtCore.QPointF(self.press_pet_pos.x() + dx, self.press_pet_pos.y() + dy)
        
        base_area = self.walk_area_for_pet_size(pet.size)
        pet.position = QtCore.QPointF(
            max(base_area.left(), min(base_area.right(), proposed.x())),
            max(base_area.top(), min(base_area.bottom(), proposed.y()))
        )
        pet.home_x = pet.position.x()
        pet.home_y = pet.position.y()
        pet.velocity = QtCore.QPointF(0, 0)
        pet.manually_placed = True
        pet.next_turn_at = time.time() + 3.0

    def mouseReleaseEvent(self, event):
        self.pressed_pet = None
        self.dragging_pet = False

    def poll(self):
        self.config.load()
        self.last_poll_time = time.time()
        
        try:
            sessions = self.reader.read_sessions(self.config)
        except Exception as e:
            print(f"Error polling CMUX: {e}")
            return
            
        active_keys = set()
        working_by_key = {}
        for s in sessions:
            key = s["key"]
            existing = self.pets.get(key)
            was_working = existing and existing.state == "working"
            
            is_agy = s["provider"] == "agy" or "agy" in s["title"].lower()
            thresh = 55.0 if is_agy else self.config.workingCpuThreshold
            exit_thresh = 50.0 if is_agy else self.config.workingCpuExitThreshold
            
            working = s["cpu"] >= exit_thresh if was_working else s["cpu"] >= thresh
            working_by_key[key] = working

        for s in sessions:
            key = s["key"]
            active_keys.add(key)
            
            pet = self.pets.get(key)
            if not pet:
                pet = PetInfo(key)
                self.pets[key] = pet
                
            pet.title = s["title"]
            pet.provider = s["provider"]
            pet.pane_ref = s["pane_ref"]
            pet.workspace_ref = s["workspace_ref"]
            pet.window_ref = s["window_ref"]
            pet.cpu = s["cpu"]
            pet.focused = s["focused"]
            pet.token_expired = s["token_expired"]
            pet.context_percentage = s.get("context_percentage", -1)
            pet.context_text = s.get("context_text", "")
            pet.status = "active"
            pet.ended_at = 0.0
            
            is_done = pet.alerting or pet.token_expired
            working = working_by_key.get(key, False)
            
            if is_done:
                pet.state = "alerting"
            elif working:
                pet.state = "working"
            else:
                pet.state = "prework"
                
            # Calculate short status summary
            status_text = ""
            if pet.status == "ended":
                status_text = f"⏹️ {translate('ended')}"
            elif pet.token_expired:
                status_text = f"❌ {translate('expired')}"
            elif s.get("last_notification") and s.get("last_notification_unread"):
                notif = s["last_notification"]
                if "permission" in notif.lower():
                    status_text = f"⚠️ {translate('approval')}"
                elif "waiting" in notif.lower():
                    status_text = f"💬 {translate('input')}"
                elif "종료" in notif or "ended" in notif.lower() or "exit" in notif.lower():
                    status_text = f"⏹️ {translate('ended')}"
                elif "완료" in notif or "done" in notif.lower() or "complete" in notif.lower():
                    status_text = f"✅ {translate('completed')}"
                else:
                    status_text = (notif[:12] + "…") if len(notif) > 14 else notif
            elif pet.state == "working":
                status_text = f"⚡ {translate('working')}"
            else:
                status_text = f"💤 {translate('prework')}"
            
            if pet.context_text:
                status_text = f"{status_text} ({pet.context_text})"
            elif pet.context_percentage >= 0:
                status_text = f"{status_text} ({pet.context_percentage}%)"
            pet.status_text = status_text

            mem_mb = s["memory_bytes"] / (1024.0 * 1024.0)
            log_val = math.log2(max(16.0, mem_mb)) - 4.0
            fraction = min(1.0, max(0.0, log_val / 6.0))
            target_size = self.config.petMinSize + (self.config.petMaxSize - self.config.petMinSize) * fraction
            
            pet.size = pet.size * 0.94 + target_size * 0.06

        dead_keys = [k for k in self.pets.keys() if k not in active_keys]
        for k in dead_keys:
            pet = self.pets[k]
            if pet.status == "ended" and time.time() - pet.ended_at <= 15.0:
                continue
            del self.pets[k]

        layout_pets = list(self.pets.values())
        for pet in layout_pets:
            if pet.status == "ended":
                pet.state = "alerting"

        # Correct state priorities and sorting
        def sort_priority(p):
            priority = 2 if p.state == "alerting" else (1 if p.state == "working" else 0)
            return (priority, p.title or p.key)
        layout_pets.sort(key=sort_priority)

        count = len(layout_pets)
        usable_width = self.width() - 36.0
        slot_width = usable_width / max(1, count)

        for i, pet in enumerate(layout_pets):
            if pet.manually_placed:
                pet.home_x = pet.position.x()
                pet.home_y = pet.position.y()
            else:
                pet.lane_width = slot_width
                pet.slot_index = i
                pet.home_x = 18.0 + slot_width * (float(i) + 0.5)
                pet.home_y = self.height() - 32.0 - (10.0 if i % 2 == 0 else 0.0)
                
            if pet.position.x() < 0:
                pet.position = QtCore.QPointF(pet.home_x, pet.home_y)

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
        
        # State rail disabled per user request
        if False and self.config.showStateRail and self.width() >= 280.0:
            self.draw_state_rails(painter)
            
        for pet in self.pets.values():
            self.draw_pet(painter, pet)

    def draw_state_rails(self, painter):
        w = self.width()
        h = self.height()
        y = h - 26.0
        
        left_w = w * 0.28
        middle_w = w * 0.38
        right_w = w * 0.26
        
        left_start = 18.0
        middle_start = 18.0 + left_w + w * 0.03
        right_start = 18.0 + w - right_w
        
        bg_brush = QtGui.QBrush(QtGui.QColor(0, 0, 0, 80))
        pen = QtGui.QPen(QtCore.Qt.PenStyle.NoPen)
        painter.setPen(pen)
        
        for start, width, label, color in [
            (left_start, left_w, f"II {translate('prework')}", QtGui.QColor(96, 107, 122)),
            (middle_start, middle_w, f"⚡ {translate('working')}", QtGui.QColor(243, 110, 20)),
            (right_start, right_w, f"✓ {translate('done')}", QtGui.QColor(31, 168, 92))
        ]:
            rect = QtCore.QRectF(start, y, width, 18.0)
            painter.setBrush(bg_brush)
            painter.drawRoundedRect(rect, 9.0, 9.0)
            
            accent_rect = QtCore.QRectF(start + 6.0, y + 6.0, 6.0, 6.0)
            painter.setBrush(QtGui.QBrush(color))
            painter.drawEllipse(accent_rect)
            
            painter.setPen(QtGui.QColor(255, 255, 255, 200))
            font = QtGui.QFont("System", 8, QtGui.QFont.Weight.Bold)
            painter.setFont(font)
            painter.drawText(
                QtCore.QRectF(start + 18.0, y, width - 24.0, 18.0),
                QtCore.Qt.AlignmentFlag.AlignVCenter | QtCore.Qt.AlignmentFlag.AlignLeft,
                label
            )
            painter.setPen(QtCore.Qt.PenStyle.NoPen)

    def draw_pet(self, painter, pet):
        s_rect = self.sprite_rect_for_pet(pet)
        frame_idx = 0
        if self.sprite_frames:
            frame_idx = int(pet.bob_phase) % len(self.sprite_frames)
            
        pixmap = self.sprite_frames[frame_idx]
        
        painter.save()
        painter.translate(s_rect.center())
        
        scale_x = -1.0 if pet.facing >= 0 else 1.0
        painter.scale(scale_x, 1.0)
        
        if pet.token_expired:
            painter.rotate(90.0 if pet.facing >= 0 else -90.0)
            
        target_draw = QtCore.QRectF(-s_rect.width() / 2.0, -s_rect.height() / 2.0, s_rect.width(), s_rect.height())
        painter.drawPixmap(target_draw.toRect(), pixmap)
        painter.restore()
        
        self.draw_status_badge(painter, pet, s_rect)
        self.draw_nameplate(painter, pet)

    def draw_status_badge(self, painter, pet, s_rect):
        badge_w = max(14.0, pet.size * 0.58)
        badge_h = max(11.0, pet.size * 0.46)
        
        if pet.token_expired:
            if pet.facing >= 0:
                badge_x = s_rect.left() - badge_w + 2.0
                badge_y = s_rect.top() + 2.0
            else:
                badge_x = s_rect.right() - 2.0
                badge_y = s_rect.top() + 2.0
        else:
            if pet.facing >= 0:
                badge_x = s_rect.left() - badge_w + 3.0
            else:
                badge_x = s_rect.right() - 3.0
            badge_y = s_rect.top() - badge_h + 4.0
            
        badge_rect = QtCore.QRectF(badge_x, badge_y, badge_w, badge_h)
        
        if pet.status == "ended":
            color = QtGui.QColor(46, 46, 46, 220)
            icon = "×"
        elif pet.token_expired:
            color = QtGui.QColor(204, 30, 30, 235)
            icon = "😵"
        elif pet.alerting:
            color = QtGui.QColor(30, 168, 92, 235)
            icon = "✓"
        elif pet.state == "working":
            color = QtGui.QColor(243, 110, 20, 235)
            icon = "⚡"
        else:
            color = QtGui.QColor(97, 107, 122, 215)
            icon = "Ⅱ"
            
        corner_rad = badge_h * 0.30
        painter.setBrush(QtGui.QBrush(color))
        painter.setPen(QtGui.QPen(QtGui.QColor(255, 255, 255), 0.8))
        painter.drawRoundedRect(badge_rect, corner_rad, corner_rad)
        
        painter.setPen(QtGui.QColor(255, 255, 255))
        font_size = max(6.5, badge_h * 0.58)
        font = QtGui.QFont("System", int(font_size), QtGui.QFont.Weight.Black)
        painter.setFont(font)
        painter.drawText(badge_rect.adjusted(0, -0.5, 0, 0), QtCore.Qt.AlignmentFlag.AlignCenter, icon)
        painter.setPen(QtCore.Qt.PenStyle.NoPen)

    def draw_nameplate(self, painter, pet):
        n_rect = self.nameplate_rect_for_pet(pet)
        
        painter.setBrush(QtGui.QBrush(QtGui.QColor(0, 0, 0, 166)))
        painter.setPen(QtCore.Qt.PenStyle.NoPen)
        painter.drawRoundedRect(n_rect, 5.0, 5.0)
        
        is_agy = pet.provider == "agy" or "agy" in pet.title.lower()
        if is_agy:
            accent = QtGui.QColor(26, 115, 232)
        elif pet.provider == "codex":
            accent = QtGui.QColor(141, 110, 99)
        elif pet.provider == "claude":
            accent = QtGui.QColor(217, 119, 6)
        else:
            accent = QtGui.QColor(117, 117, 117)
            
        strip_rect = QtCore.QRectF(n_rect.left(), n_rect.bottom() - 3.0, n_rect.width(), 3.0)
        painter.setBrush(QtGui.QBrush(accent))
        painter.drawRoundedRect(strip_rect, 1.5, 1.5)
        
        label = pet.title or pet.provider or "cmux"
        painter.setPen(QtGui.QColor(255, 255, 255))
        font = QtGui.QFont("System", 8, QtGui.QFont.Weight.Bold)
        painter.setFont(font)
        
        metrics = QtGui.QFontMetrics(font)
        elided = metrics.elidedText(label, QtCore.Qt.TextElideMode.ElideRight, int(n_rect.width() - 8.0))
        
        status_text = getattr(pet, "status_text", "")
        if status_text:
            # Draw main title at the top half
            title_rect = QtCore.QRectF(n_rect.left() + 4.0, n_rect.top() + 3.0, n_rect.width() - 8.0, 14.0)
            painter.drawText(title_rect, QtCore.Qt.AlignmentFlag.AlignCenter, elided)
            
            # Draw subtitle below
            sub_font = QtGui.QFont("System", 7, QtGui.QFont.Weight.Medium)
            painter.setFont(sub_font)
            painter.setPen(QtGui.QColor(218, 220, 224, 230))
            sub_rect = QtCore.QRectF(n_rect.left() + 4.0, n_rect.top() + 17.0, n_rect.width() - 8.0, 12.0)
            painter.drawText(sub_rect, QtCore.Qt.AlignmentFlag.AlignCenter, status_text)
        else:
            painter.drawText(
                n_rect.adjusted(4.0, 0.0, -4.0, -3.0),
                QtCore.Qt.AlignmentFlag.AlignCenter,
                elided
            )
        painter.setPen(QtCore.Qt.PenStyle.NoPen)

def main():
    app = QtWidgets.QApplication(sys.argv)
    app.setAttribute(QtCore.Qt.ApplicationAttribute.AA_UseHighDpiPixmaps, True)
    
    screens = app.screens()
    print(f"Detected {len(screens)} monitors. Initializing cross-platform overlay.")
    
    sorted_screens = sorted(list(enumerate(screens)), key=lambda s: s[1].geometry().x())
    leftmost_idx = sorted_screens[0][0]
    
    overlay = OverlayWindow(screen_index=leftmost_idx)
    overlay.show()
    
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
