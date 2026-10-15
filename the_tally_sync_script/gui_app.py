"""
TyreX Tally Sync - Control Center & Configuration Management Tool
Standalone GUI application to manage background sync service, edit .env settings,
test connections, and view real-time sync logs.
"""
from __future__ import annotations

import os
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import customtkinter as ctk
import psutil
import requests
from dotenv import dotenv_values, set_key

from sync.config import (
    ROOT_DIR,
    supabase_key,
    supabase_url,
    sync_interval_seconds,
    sync_since_date,
    sync_until_date,
    tally_host,
    tally_port,
    tally_url,
)
from sync.logutil import log_path
from sync.tally_xml import fetch_current_company

# Appearance
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

SYNC_SERVICE_EXE = "TyrexTallySync.exe"


def get_env_file_path() -> Path:
    sync_env = ROOT_DIR / "tally_sync.env"
    if sync_env.exists():
        return sync_env
    dot_env = ROOT_DIR / ".env"
    if dot_env.exists():
        return dot_env
    return sync_env


def get_service_process() -> psutil.Process | None:
    """Finds running TyrexTallySync.exe background process if any."""
    for proc in psutil.process_iter(["pid", "name"]):
        try:
            if proc.info["name"] and proc.info["name"].lower() == SYNC_SERVICE_EXE.lower():
                return proc
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return None


def is_service_running() -> bool:
    return get_service_process() is not None


class TyrexControlCenterApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("TyreX Tally Sync - Control Center")
        self.geometry("860x650")
        self.minsize(780, 560)

        ico_file = ROOT_DIR / "app_icon.ico"
        if ico_file.exists():
            try:
                self.iconbitmap(str(ico_file))
            except Exception:
                pass

        self.env_path = get_env_file_path()
        self.log_file = log_path()
        self.last_log_pos = 0

        self._build_ui()
        self._load_env_to_inputs()
        self._start_status_poller()
        self._start_log_streamer()

    def _build_ui(self):
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        # Header Frame
        self.header_frame = ctk.CTkFrame(self, corner_radius=10, fg_color="#18181b")
        self.header_frame.grid(row=0, column=0, padx=16, pady=(14, 8), sticky="ew")
        self.header_frame.grid_columnconfigure(1, weight=1)

        self.title_label = ctk.CTkLabel(
            self.header_frame,
            text="⚡ TyreX Tally Sync",
            font=ctk.CTkFont(size=20, weight="bold"),
            text_color="#60a5fa",
        )
        self.title_label.grid(row=0, column=0, padx=16, pady=(10, 2), sticky="w")

        self.service_status_badge = ctk.CTkLabel(
            self.header_frame,
            text="● Checking Service...",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#facc15",
            fg_color="#713f12",
            corner_radius=6,
            padx=10,
            pady=3,
        )
        self.service_status_badge.grid(row=0, column=2, padx=16, pady=10, sticky="e")

        self.sub_label = ctk.CTkLabel(
            self.header_frame,
            text="Central Management Tool for Background Tally Synchronization Service",
            font=ctk.CTkFont(size=12),
            text_color="#94a3b8",
        )
        self.sub_label.grid(row=1, column=0, columnspan=2, padx=16, pady=(0, 10), sticky="w")

        # Tabview
        self.tabview = ctk.CTkTabview(self, corner_radius=10)
        self.tabview.grid(row=1, column=0, padx=16, pady=8, sticky="nsew")

        self.tab_dashboard = self.tabview.add("📊 Service Monitor")
        self.tab_config = self.tabview.add("⚙️ Settings (.env)")
        self.tab_logs = self.tabview.add("📋 Live Logs")

        self._build_dashboard_tab()
        self._build_config_tab()
        self._build_logs_tab()

        # Footer Frame
        self.footer_frame = ctk.CTkFrame(self, height=44, corner_radius=8, fg_color="#0f172a")
        self.footer_frame.grid(row=2, column=0, padx=16, pady=(4, 12), sticky="ew")
        self.footer_frame.grid_columnconfigure(1, weight=1)

        self.footer_info = ctk.CTkLabel(
            self.footer_frame,
            text=f"Config: {self.env_path.name} | Log File: {self.log_file.name}",
            font=ctk.CTkFont(size=11),
            text_color="#64748b",
        )
        self.footer_info.grid(row=0, column=0, padx=12, pady=8, sticky="w")

        self.btn_restart_service_footer = ctk.CTkButton(
            self.footer_frame,
            text="🔄 Restart Service",
            width=130,
            height=28,
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color="#2563eb",
            hover_color="#1d4ed8",
            command=self.restart_background_service,
        )
        self.btn_restart_service_footer.grid(row=0, column=2, padx=10, pady=6, sticky="e")

    # =========================================================================
    # TAB 1: Service Monitor
    # =========================================================================
    def _build_dashboard_tab(self):
        tab = self.tab_dashboard
        tab.grid_columnconfigure((0, 1), weight=1)

        # Card 1: Background Service Status
        self.card_service = ctk.CTkFrame(tab, corner_radius=10, fg_color="#1e293b")
        self.card_service.grid(row=0, column=0, padx=8, pady=8, sticky="nsew")
        self.card_service.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            self.card_service,
            text="🖥️ Background Daemon Status",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#93c5fd",
        ).grid(row=0, column=0, padx=12, pady=(10, 4), sticky="w")

        self.lbl_daemon_info = ctk.CTkLabel(
            self.card_service,
            text="Service Process: Checking...",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#f8fafc",
        )
        self.lbl_daemon_info.grid(row=1, column=0, padx=12, pady=2, sticky="w")

        self.lbl_daemon_detail = ctk.CTkLabel(
            self.card_service,
            text="Process: TyrexTallySync.exe (Auto-starts with Windows)",
            font=ctk.CTkFont(size=11),
            text_color="#94a3b8",
        )
        self.lbl_daemon_detail.grid(row=2, column=0, padx=12, pady=(2, 10), sticky="w")

        # Card 2: Tally Connection Status
        self.card_tally = ctk.CTkFrame(tab, corner_radius=10, fg_color="#1e293b")
        self.card_tally.grid(row=0, column=1, padx=8, pady=8, sticky="nsew")
        self.card_tally.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            self.card_tally,
            text="🏢 Tally Prime Connection",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#93c5fd",
        ).grid(row=0, column=0, padx=12, pady=(10, 4), sticky="w")

        self.lbl_tally_comp = ctk.CTkLabel(
            self.card_tally,
            text="Active Company: Checking...",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#f8fafc",
        )
        self.lbl_tally_comp.grid(row=1, column=0, padx=12, pady=2, sticky="w")

        self.lbl_tally_url = ctk.CTkLabel(
            self.card_tally,
            text=f"Endpoint: {tally_url()}",
            font=ctk.CTkFont(size=11),
            text_color="#94a3b8",
        )
        self.lbl_tally_url.grid(row=2, column=0, padx=12, pady=(2, 10), sticky="w")

        # Service Control Buttons Bar
        ctrl_bar = ctk.CTkFrame(tab, corner_radius=10, fg_color="#18181b")
        ctrl_bar.grid(row=1, column=0, columnspan=2, padx=8, pady=10, sticky="ew")

        ctk.CTkLabel(
            ctrl_bar,
            text="Service Controls:",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#cbd5e1",
        ).pack(side="left", padx=14, pady=10)

        self.btn_start_service = ctk.CTkButton(
            ctrl_bar,
            text="▶ Start Service",
            width=130,
            fg_color="#10b981",
            hover_color="#059669",
            command=self.start_background_service,
        )
        self.btn_start_service.pack(side="left", padx=6, pady=10)

        self.btn_restart_service = ctk.CTkButton(
            ctrl_bar,
            text="🔄 Restart Service",
            width=130,
            fg_color="#2563eb",
            hover_color="#1d4ed8",
            command=self.restart_background_service,
        )
        self.btn_restart_service.pack(side="left", padx=6, pady=10)

        self.btn_stop_service = ctk.CTkButton(
            ctrl_bar,
            text="⏹ Stop Service",
            width=130,
            fg_color="#ef4444",
            hover_color="#dc2626",
            command=self.stop_background_service,
        )
        self.btn_stop_service.pack(side="left", padx=6, pady=10)

        self.btn_check_conn = ctk.CTkButton(
            ctrl_bar,
            text="⚡ Check Connections",
            width=150,
            fg_color="#475569",
            hover_color="#334155",
            command=self.check_all_connections,
        )
        self.btn_check_conn.pack(side="left", padx=6, pady=10)

        # Recent Logs preview
        ctk.CTkLabel(
            tab,
            text="Recent Activity Log Preview:",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#cbd5e1",
        ).grid(row=2, column=0, padx=8, pady=(8, 2), sticky="w")

        self.dash_log_box = ctk.CTkTextbox(
            tab,
            height=180,
            font=ctk.CTkFont(family="Consolas", size=11),
            text_color="#a7f3d0",
            fg_color="#090d16",
        )
        self.dash_log_box.grid(row=3, column=0, columnspan=2, padx=8, pady=4, sticky="nsew")
        tab.grid_rowconfigure(3, weight=1)

    # =========================================================================
    # TAB 2: Settings & Configuration (.env Editor)
    # =========================================================================
    def _build_config_tab(self):
        tab = self.tab_config
        tab.grid_columnconfigure((0, 1), weight=1)

        scroll = ctk.CTkScrollableFrame(tab, fg_color="transparent")
        scroll.grid(row=0, column=0, columnspan=2, sticky="nsew", padx=4, pady=4)
        tab.grid_rowconfigure(0, weight=1)
        scroll.grid_columnconfigure((0, 1), weight=1)

        # Section 1: Tally
        tally_sec = ctk.CTkFrame(scroll, corner_radius=10, fg_color="#1e293b")
        tally_sec.grid(row=0, column=0, columnspan=2, padx=6, pady=6, sticky="ew")
        tally_sec.grid_columnconfigure((0, 1), weight=1)

        ctk.CTkLabel(
            tally_sec,
            text="🏢 Tally Prime Connection",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#93c5fd",
        ).grid(row=0, column=0, columnspan=2, padx=12, pady=(8, 4), sticky="w")

        ctk.CTkLabel(tally_sec, text="Tally Host:", font=ctk.CTkFont(size=12)).grid(
            row=1, column=0, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_tally_host = ctk.CTkEntry(tally_sec, placeholder_text="localhost")
        self.entry_tally_host.grid(row=2, column=0, padx=12, pady=(0, 8), sticky="ew")

        ctk.CTkLabel(tally_sec, text="Tally Port (Default 9000):", font=ctk.CTkFont(size=12)).grid(
            row=1, column=1, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_tally_port = ctk.CTkEntry(tally_sec, placeholder_text="9000")
        self.entry_tally_port.grid(row=2, column=1, padx=12, pady=(0, 8), sticky="ew")

        btn_tally_box = ctk.CTkFrame(tally_sec, fg_color="transparent")
        btn_tally_box.grid(row=3, column=0, columnspan=2, padx=12, pady=(0, 10), sticky="ew")

        self.btn_test_tally = ctk.CTkButton(
            btn_tally_box,
            text="⚡ Test Tally Connection",
            width=160,
            fg_color="#3b82f6",
            hover_color="#2563eb",
            command=self.test_tally_connection,
        )
        self.btn_test_tally.pack(side="left")

        self.lbl_tally_test_res = ctk.CTkLabel(
            btn_tally_box, text="", font=ctk.CTkFont(size=11, weight="bold"), text_color="#94a3b8"
        )
        self.lbl_tally_test_res.pack(side="left", padx=12)

        # Section 2: Supabase
        supa_sec = ctk.CTkFrame(scroll, corner_radius=10, fg_color="#1e293b")
        supa_sec.grid(row=1, column=0, columnspan=2, padx=6, pady=6, sticky="ew")
        supa_sec.grid_columnconfigure((0, 1), weight=1)

        ctk.CTkLabel(
            supa_sec,
            text="☁️ Supabase Cloud Database",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#93c5fd",
        ).grid(row=0, column=0, columnspan=2, padx=12, pady=(8, 4), sticky="w")

        ctk.CTkLabel(supa_sec, text="Supabase URL:", font=ctk.CTkFont(size=12)).grid(
            row=1, column=0, columnspan=2, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_supa_url = ctk.CTkEntry(supa_sec, placeholder_text="https://xxxx.supabase.co")
        self.entry_supa_url.grid(row=2, column=0, columnspan=2, padx=12, pady=(0, 8), sticky="ew")

        ctk.CTkLabel(supa_sec, text="Supabase API Key (Anon / Service Role):", font=ctk.CTkFont(size=12)).grid(
            row=3, column=0, columnspan=2, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_supa_key = ctk.CTkEntry(supa_sec, show="•")
        self.entry_supa_key.grid(row=4, column=0, columnspan=2, padx=12, pady=(0, 8), sticky="ew")

        supa_btn_box = ctk.CTkFrame(supa_sec, fg_color="transparent")
        supa_btn_box.grid(row=5, column=0, columnspan=2, padx=12, pady=(0, 10), sticky="ew")

        self.btn_test_supa = ctk.CTkButton(
            supa_btn_box,
            text="⚡ Test Cloud Connection",
            width=160,
            fg_color="#3b82f6",
            hover_color="#2563eb",
            command=self.test_supabase_connection,
        )
        self.btn_test_supa.pack(side="left", padx=(0, 10))

        self.btn_toggle_show_key = ctk.CTkButton(
            supa_btn_box,
            text="👁 Show Key",
            width=90,
            fg_color="#475569",
            hover_color="#334155",
            command=self.toggle_show_key,
        )
        self.btn_toggle_show_key.pack(side="left")

        self.lbl_supa_test_res = ctk.CTkLabel(
            supa_btn_box, text="", font=ctk.CTkFont(size=11, weight="bold"), text_color="#94a3b8"
        )
        self.lbl_supa_test_res.pack(side="left", padx=12)

        # Section 3: Intervals
        sync_sec = ctk.CTkFrame(scroll, corner_radius=10, fg_color="#1e293b")
        sync_sec.grid(row=2, column=0, columnspan=2, padx=6, pady=6, sticky="ew")
        sync_sec.grid_columnconfigure((0, 1, 2), weight=1)

        ctk.CTkLabel(
            sync_sec,
            text="⏱️ Sync Schedule & Date Filters",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#93c5fd",
        ).grid(row=0, column=0, columnspan=3, padx=12, pady=(8, 4), sticky="w")

        ctk.CTkLabel(sync_sec, text="Interval (seconds):", font=ctk.CTkFont(size=12)).grid(
            row=1, column=0, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_interval = ctk.CTkEntry(sync_sec, placeholder_text="60")
        self.entry_interval.grid(row=2, column=0, padx=12, pady=(0, 8), sticky="ew")

        ctk.CTkLabel(sync_sec, text="Sync Since (YYYY-MM-DD):", font=ctk.CTkFont(size=12)).grid(
            row=1, column=1, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_since = ctk.CTkEntry(sync_sec, placeholder_text="2026-09-26")
        self.entry_since.grid(row=2, column=1, padx=12, pady=(0, 8), sticky="ew")

        ctk.CTkLabel(sync_sec, text="Sync Until (YYYY-MM-DD):", font=ctk.CTkFont(size=12)).grid(
            row=1, column=2, padx=12, pady=(4, 2), sticky="w"
        )
        self.entry_until = ctk.CTkEntry(sync_sec, placeholder_text="2027-09-26")
        self.entry_until.grid(row=2, column=2, padx=12, pady=(0, 8), sticky="ew")

        # Save Button
        save_box = ctk.CTkFrame(scroll, fg_color="transparent")
        save_box.grid(row=3, column=0, columnspan=2, padx=6, pady=(10, 4), sticky="ew")

        self.btn_save_config = ctk.CTkButton(
            save_box,
            text="💾 Save Settings & Restart Background Service",
            height=36,
            font=ctk.CTkFont(size=13, weight="bold"),
            fg_color="#10b981",
            hover_color="#059669",
            command=self.save_settings_and_restart,
        )
        self.btn_save_config.pack(side="left", padx=(0, 10))

        self.lbl_save_status = ctk.CTkLabel(
            save_box, text="", font=ctk.CTkFont(size=12, weight="bold"), text_color="#10b981"
        )
        self.lbl_save_status.pack(side="left", padx=8)

    # =========================================================================
    # TAB 3: Logs
    # =========================================================================
    def _build_logs_tab(self):
        tab = self.tab_logs
        tab.grid_columnconfigure(0, weight=1)
        tab.grid_rowconfigure(1, weight=1)

        tool_frame = ctk.CTkFrame(tab, height=36, fg_color="#1e293b", corner_radius=8)
        tool_frame.grid(row=0, column=0, padx=6, pady=(6, 4), sticky="ew")

        self.btn_clear_logs = ctk.CTkButton(
            tool_frame,
            text="🧹 Clear View",
            width=90,
            height=26,
            fg_color="#475569",
            hover_color="#334155",
            command=self.clear_logs,
        )
        self.btn_clear_logs.pack(side="left", padx=8, pady=5)

        self.btn_open_logfile = ctk.CTkButton(
            tool_frame,
            text="📂 Open tally_sync.log in Notepad",
            width=180,
            height=26,
            fg_color="#475569",
            hover_color="#334155",
            command=self.open_log_in_notepad,
        )
        self.btn_open_logfile.pack(side="left", padx=8, pady=5)

        self.auto_scroll_var = ctk.BooleanVar(value=True)
        self.chk_auto_scroll = ctk.CTkCheckBox(
            tool_frame, text="Auto-Scroll", variable=self.auto_scroll_var, font=ctk.CTkFont(size=11)
        )
        self.chk_auto_scroll.pack(side="right", padx=12, pady=5)

        self.full_log_box = ctk.CTkTextbox(
            tab,
            font=ctk.CTkFont(family="Consolas", size=11),
            text_color="#e2e8f0",
            fg_color="#090d16",
        )
        self.full_log_box.grid(row=1, column=0, padx=6, pady=4, sticky="nsew")

    # =========================================================================
    # Actions & Handlers
    # =========================================================================
    def _load_env_to_inputs(self):
        vals = dotenv_values(self.env_path) if self.env_path.exists() else {}

        self.entry_tally_host.delete(0, "end")
        self.entry_tally_host.insert(0, vals.get("TALLY_HOST") or tally_host())

        self.entry_tally_port.delete(0, "end")
        self.entry_tally_port.insert(0, str(vals.get("TALLY_PORT") or tally_port()))

        self.entry_supa_url.delete(0, "end")
        self.entry_supa_url.insert(0, vals.get("SUPABASE_URL") or supabase_url())

        self.entry_supa_key.delete(0, "end")
        self.entry_supa_key.insert(0, vals.get("SUPABASE_KEY") or supabase_key())

        self.entry_interval.delete(0, "end")
        self.entry_interval.insert(0, str(vals.get("SYNC_INTERVAL_SECONDS") or sync_interval_seconds()))

        self.entry_since.delete(0, "end")
        self.entry_since.insert(0, str(vals.get("SYNC_SINCE") or sync_since_date()))

        self.entry_until.delete(0, "end")
        self.entry_until.insert(0, str(vals.get("SYNC_UNTIL") or sync_until_date()))

    def toggle_show_key(self):
        if self.entry_supa_key.cget("show") == "":
            self.entry_supa_key.configure(show="•")
            self.btn_toggle_show_key.configure(text="👁 Show Key")
        else:
            self.entry_supa_key.configure(show="")
            self.btn_toggle_show_key.configure(text="🔒 Hide Key")

    def test_tally_connection(self):
        host = self.entry_tally_host.get().strip() or "localhost"
        port = self.entry_tally_port.get().strip() or "9000"
        url = f"http://{host}:{port}"
        self.lbl_tally_test_res.configure(text="Testing...", text_color="#facc15")
    def test_tally_connection(self):
        self.save_settings(silent=True)
        host = self.entry_tally_host.get().strip() or "127.0.0.1"
        port = self.entry_tally_port.get().strip() or "9000"
        url = f"http://{host}:{port}"
        self.lbl_tally_test_res.configure(text="Connecting to Tally...", text_color="#facc15")
        self.update_idletasks()

        def _test():
            try:
                comp = fetch_current_company(url=url, force_fresh=True)
                if comp and comp.get("tally_company_name"):
                    cname = comp["tally_company_name"]
                    self.lbl_tally_test_res.configure(
                        text=f"✓ Connected! ({cname})", text_color="#10b981"
                    )
                    self.lbl_tally_comp.configure(text=f"Active Company: {cname}")
                else:
                    self.lbl_tally_test_res.configure(
                        text=f"✓ Tally responding at {url} (No company open)", text_color="#60a5fa"
                    )
            except Exception as e:
                self.lbl_tally_test_res.configure(
                    text=f"✗ Cannot reach Tally: {e}", text_color="#ef4444"
                )

        threading.Thread(target=_test, daemon=True).start()

    def test_supabase_connection(self):
        self.save_settings(silent=True)
        url = self.entry_supa_url.get().strip()
        key = self.entry_supa_key.get().strip()
        if not url or not key:
            self.lbl_supa_test_res.configure(text="✗ URL and Key required", text_color="#ef4444")
            return

        self.lbl_supa_test_res.configure(text="Testing Cloud DB...", text_color="#facc15")
        self.update_idletasks()

        def _test():
            try:
                clean_url = url.rstrip("/")
                if clean_url.endswith("/rest/v1"):
                    clean_url = clean_url[: -len("/rest/v1")]
                headers = {"apikey": key, "Authorization": f"Bearer {key}"}

                test_endpoints = [
                    f"{clean_url}/rest/v1/tally_companies?select=id&limit=1",
                    f"{clean_url}/rest/v1/user_companies?select=id&limit=1",
                    f"{clean_url}/rest/v1/tally_ledgers?select=id&limit=1",
                ]
                authorized = False
                last_err = "Auth failed"
                for ep in test_endpoints:
                    try:
                        r = requests.get(ep, headers=headers, timeout=8)
                        if r.status_code in (200, 204, 206):
                            authorized = True
                            break
                        elif r.status_code == 404 and "PGRST205" in r.text:
                            authorized = True
                            break
                        else:
                            last_err = f"Status {r.status_code}"
                    except Exception as ex:
                        last_err = str(ex)

                if authorized:
                    self.lbl_supa_test_res.configure(
                        text="✓ Supabase Connected & Authorized!", text_color="#10b981"
                    )
                else:
                    self.lbl_supa_test_res.configure(
                        text=f"✗ {last_err}", text_color="#ef4444"
                    )
            except Exception as e:
                self.lbl_supa_test_res.configure(
                    text=f"✗ Connection error: {e}", text_color="#ef4444"
                )

        threading.Thread(target=_test, daemon=True).start()

    def check_all_connections(self):
        self.test_tally_connection()
        self.test_supabase_connection()

    def start_background_service(self):
        """Starts the TyrexTallySync.exe daemon in the background without freezing UI."""
        self.save_settings(silent=True)
        def _run():
            if is_service_running():
                return
            exe_path = ROOT_DIR / SYNC_SERVICE_EXE
            if not exe_path.exists():
                dist_exe = ROOT_DIR / "dist" / SYNC_SERVICE_EXE
                if dist_exe.exists():
                    exe_path = dist_exe

            try:
                CREATE_NO_WINDOW = 0x08000000
                subprocess.Popen([str(exe_path), "--watch"], creationflags=CREATE_NO_WINDOW)
            except Exception as e:
                print(f"Error starting service: {e}")
        threading.Thread(target=_run, daemon=True).start()

    def stop_background_service(self):
        """Kills any running TyrexTallySync.exe daemon in the background."""
        def _run():
            try:
                if sys.platform == "win32":
                    subprocess.run(
                        ["taskkill", "/F", "/IM", SYNC_SERVICE_EXE],
                        capture_output=True,
                        creationflags=0x08000000,
                    )
            except Exception as e:
                print(f"Error stopping service: {e}")
        threading.Thread(target=_run, daemon=True).start()

    def restart_background_service(self):
        self.save_settings(silent=True)
        def _run():
            self.stop_background_service()
            time.sleep(0.6)
            self.start_background_service()
        threading.Thread(target=_run, daemon=True).start()

    def save_settings(self, silent: bool = False) -> bool:
        env_file = str(self.env_path)
        try:
            if not self.env_path.exists():
                self.env_path.touch()

            host = self.entry_tally_host.get().strip() or "127.0.0.1"
            port = self.entry_tally_port.get().strip() or "9000"
            supa_u = self.entry_supa_url.get().strip()
            supa_k = self.entry_supa_key.get().strip()
            interval = self.entry_interval.get().strip()
            since = self.entry_since.get().strip()
            until = self.entry_until.get().strip()

            set_key(env_file, "TALLY_HOST", host)
            set_key(env_file, "TALLY_PORT", port)
            set_key(env_file, "SUPABASE_URL", supa_u)
            set_key(env_file, "SUPABASE_KEY", supa_k)
            set_key(env_file, "SYNC_INTERVAL_SECONDS", interval)
            set_key(env_file, "SYNC_SINCE", since)
            set_key(env_file, "SYNC_UNTIL", until)

            os.environ["TALLY_HOST"] = host
            os.environ["TALLY_PORT"] = port
            os.environ["SUPABASE_URL"] = supa_u
            os.environ["SUPABASE_KEY"] = supa_k
            os.environ["SYNC_INTERVAL_SECONDS"] = interval
            os.environ["SYNC_SINCE"] = since
            os.environ["SYNC_UNTIL"] = until

            self.lbl_tally_url.configure(text=f"Endpoint: http://{host}:{port}")
            if not silent:
                self.lbl_save_status.configure(
                    text="✓ Saved successfully!", text_color="#10b981"
                )
            return True
        except Exception as e:
            if not silent:
                self.lbl_save_status.configure(text=f"✗ Error saving: {e}", text_color="#ef4444")
            return False

    def save_settings_and_restart(self):
        if self.save_settings(silent=False):
            self.lbl_save_status.configure(
                text="✓ Saved! Restarting background service...", text_color="#10b981"
            )
            self.restart_background_service()

    def clear_logs(self):
        self.full_log_box.delete("1.0", "end")
        self.dash_log_box.delete("1.0", "end")

    def open_log_in_notepad(self):
        if sys.platform == "win32" and self.log_file.exists():
            os.system(f'notepad.exe "{self.log_file}"')

    def _start_status_poller(self):
        """Asynchronous background worker: never blocks the Tkinter UI."""
        def _worker():
            while True:
                proc = get_service_process()
                is_running = proc is not None
                pid = proc.pid if proc else None
                mem = 0.0
                cpu = 0.0
                if proc:
                    try:
                        mem = proc.memory_info().rss / (1024 * 1024)
                        cpu = proc.cpu_percent(interval=0.0)
                    except Exception:
                        pass

                host = os.getenv("TALLY_HOST", "127.0.0.1")
                port = os.getenv("TALLY_PORT", "9000")
                url = f"http://{host}:{port}"
                company_text = "Active Company: Checking..."
                try:
                    # Quick non-blocking probe with 1.5s timeout
                    comp = fetch_current_company(url=url)
                    if comp and comp.get("tally_company_name"):
                        company_text = f"Active Company: {comp['tally_company_name']}"
                    else:
                        company_text = "Active Company: No Company Open"
                except Exception:
                    company_text = "Active Company: Tally Not Responding"

                def _apply(running=is_running, p=pid, m=mem, c=cpu, c_text=company_text, endpoint=url):
                    try:
                        self.lbl_tally_url.configure(text=f"Endpoint: {endpoint}")
                        self.lbl_tally_comp.configure(text=c_text)
                        if running:
                            self.service_status_badge.configure(
                                text="● Service Running (24/7)", text_color="#10b981", fg_color="#064e3b"
                            )
                            self.lbl_daemon_info.configure(
                                text=f"Service Active (PID {p}, {m:.1f} MB, {c:.1f}% CPU)"
                            )
                        else:
                            self.service_status_badge.configure(
                                text="● Service Stopped", text_color="#ef4444", fg_color="#450a0a"
                            )
                            self.lbl_daemon_info.configure(text="Background Service is NOT Running")
                    except Exception:
                        pass

                try:
                    self.after(0, _apply)
                except Exception:
                    break
                time.sleep(2.5)

        threading.Thread(target=_worker, daemon=True).start()

    def _start_log_streamer(self):
        """Reads new lines from tally_sync.log smoothly."""
        def _read_logs():
            if self.log_file.exists():
                try:
                    with open(self.log_file, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(self.last_log_pos)
                        new_text = f.read(32768)  # max 32KB per slice for snappy UI
                        if new_text:
                            self.last_log_pos = f.tell()
                            self.full_log_box.insert("end", new_text)
                            self.dash_log_box.insert("end", new_text)

                            if self.auto_scroll_var.get():
                                self.full_log_box.see("end")
                                self.dash_log_box.see("end")
                except Exception:
                    pass

            self.after(1500, _read_logs)

        # Initial load: read last 12KB
        if self.log_file.exists():
            try:
                size = self.log_file.stat().st_size
                start_pos = max(0, size - 12000)
                with open(self.log_file, "r", encoding="utf-8", errors="replace") as f:
                    f.seek(start_pos)
                    initial_text = f.read()
                    self.last_log_pos = f.tell()
                    self.full_log_box.insert("end", initial_text)
                    self.dash_log_box.insert("end", initial_text)
                    self.full_log_box.see("end")
                    self.dash_log_box.see("end")
            except Exception:
                pass

        self.after(1000, _read_logs)


def launch_control_center():
    app = TyrexControlCenterApp()
    app.mainloop()


if __name__ == "__main__":
    launch_control_center()
