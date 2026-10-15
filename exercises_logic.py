"""
Module xu ly logic nhan dien cu dong canh tay cho 5 bai tap phuc hoi chuc nang.
Tuan thu chat che JSON Contract 1.0.0 va Kich ban Game 2D Pixel PHCN So 01.
Tac gia: Nong Thi Hong Lan (AI & Computer Vision Backend)
"""

import math
import time
from typing import Dict, Any, List, Optional, Tuple


class LandmarkPoint:
    """Dai dien cho mot diem khop xuong sau khi da duoc loc nhieu."""
    __slots__ = ('x', 'y', 'z', 'visibility')

    def __init__(self, x: float, y: float, z: float, visibility: float = 1.0):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)
        self.visibility = float(visibility)


class EMAFilter:
    """
    Bo loc tin hieu Exponential Moving Average (EMA) giup giam rung giat (jitter)
    khi nguoi benh thuc hien cu dong hoac giu tinh (hold).
    Cong thuc: smoothed = alpha * curr + (1 - alpha) * prev
    """
    def __init__(self, alpha: float = 0.32):
        self.alpha = alpha
        self.prev_landmarks: Optional[List[LandmarkPoint]] = None

    def filter(self, raw_landmarks) -> List[LandmarkPoint]:
        if not raw_landmarks:
            return []

        if self.prev_landmarks is None or len(self.prev_landmarks) != len(raw_landmarks):
            self.prev_landmarks = [
                LandmarkPoint(lm.x, lm.y, lm.z, getattr(lm, 'visibility', 1.0))
                for lm in raw_landmarks
            ]
            return self.prev_landmarks

        smoothed: List[LandmarkPoint] = []
        for curr, prev in zip(raw_landmarks, self.prev_landmarks):
            curr_vis = getattr(curr, 'visibility', 1.0)
            sm_x = self.alpha * curr.x + (1.0 - self.alpha) * prev.x
            sm_y = self.alpha * curr.y + (1.0 - self.alpha) * prev.y
            sm_z = self.alpha * curr.z + (1.0 - self.alpha) * prev.z
            sm_vis = self.alpha * curr_vis + (1.0 - self.alpha) * prev.visibility
            smoothed.append(LandmarkPoint(sm_x, sm_y, sm_z, sm_vis))

        self.prev_landmarks = smoothed
        return smoothed

    def reset(self):
        self.prev_landmarks = None


class ExercisesEvaluator:
    """
    Bo danh gia y khoa va may trang thai cu dong (Movement State Machine).
    Xu ly ca 5 bai tap, che do do ROM (Calibration) va sinh su kien Repetition/Hold.
    """

    def __init__(self):
        self.filter = EMAFilter(alpha=0.32)

        # Cau hinh va trang thai cho tung bai tap
        self.exercise_states: Dict[str, Dict[str, Any]] = {
            "scapular_retraction": self._default_exercise_state(hold_ms=700),
            "wall_abduction_external_rotation": self._default_exercise_state(hold_ms=5000),
            "horizontal_shoulder_adduction": self._default_exercise_state(hold_ms=5000),
            "hands_behind_head": self._default_exercise_state(hold_ms=5000),
            "cross_body_shoulder_stretch": self._default_exercise_state(hold_ms=30000),
        }

        # Trang thai hieu chuan (Calibration)
        self.calibration_active = False
        self.calib_exercise_id = "scapular_retraction"
        self.calib_target_side = "both"
        self.calib_duration_ms = 5000
        self.calib_start_time = 0.0
        self.calib_max_rom_left = 0.0
        self.calib_max_rom_right = 0.0
        self.calib_max_rom_combined = 0.0
        self.calib_last_emit_time = 0.0

        # Quan ly tam dung (Pause)
        self.is_paused = False

    def _default_exercise_state(self, hold_ms: int) -> Dict[str, Any]:
        return {
            "movement_state": "ready",  # ready, contracting, target_reached, holding, returning
            "rep_count": 0,
            "current_rep_id": "",
            "movement_start_time": 0.0,
            "hold_start_time": 0.0,
            "last_hold_emit_time": 0.0,
            "hold_grace_start_time": 0.0,
            "target_rom_ratio": 0.85,
            "calibrated_max_rom": 0.0,
            "target_rom_value": 0.0,
            "hold_duration_ms": hold_ms,
            "min_movement_duration_ms": 1500,
            "max_movement_duration_ms": 6000,
            "target_side": "both",
            "active_stretch_side": "none",
            "last_rom_progress": 0.0,
            "last_hold_progress": 0.0,
            "peak_rom_achieved": 0.0,
        }

    # ==========================
    # TOAN HOC & VECTOR CO BAN
    # ==========================
    @staticmethod
    def calculate_angle(p1: LandmarkPoint, p2: LandmarkPoint, p3: LandmarkPoint) -> float:
        """
        Tinh goc tai dinh p2 tao boi p1-p2-p3 (do tu 0 den 180 do).
        """
        radians = math.atan2(p3.y - p2.y, p3.x - p2.x) - math.atan2(p1.y - p2.y, p1.x - p2.x)
        angle = abs(math.degrees(radians))
        if angle > 180.0:
            angle = 360.0 - angle
        return angle

    @staticmethod
    def calculate_angle_3d(p1: LandmarkPoint, p2: LandmarkPoint, p3: LandmarkPoint) -> float:
        """Tinh goc tai dinh p2 tao boi p1-p2-p3 trong khong gian 3D (do tu 0 den 180 do)."""
        v1 = (p1.x - p2.x, p1.y - p2.y, p1.z - p2.z)
        v2 = (p3.x - p2.x, p3.y - p2.y, p3.z - p2.z)
        dot = v1[0]*v2[0] + v1[1]*v2[1] + v1[2]*v2[2]
        mag1 = math.sqrt(v1[0]**2 + v1[1]**2 + v1[2]**2)
        mag2 = math.sqrt(v2[0]**2 + v2[1]**2 + v2[2]**2)
        if mag1 < 1e-6 or mag2 < 1e-6:
            return 90.0
        cos_val = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return math.degrees(math.acos(cos_val))

    @staticmethod
    def calculate_2d_distance(p1: LandmarkPoint, p2: LandmarkPoint) -> float:
        """Khoang cach Euclid 2D giua 2 diem."""
        return math.sqrt((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2)

    @staticmethod
    def calculate_3d_distance(p1: LandmarkPoint, p2: LandmarkPoint) -> float:
        """Khoang cach Euclid 3D giua 2 diem."""
        return math.sqrt((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2 + (p1.z - p2.z) ** 2)

    # ==========================
    # CAU HINH PHIEN TAP & CALIBRATION
    # ==========================
    def configure_exercise(self, exercise_id: str, config: Dict[str, Any]):
        """Khoi tao/cap nhat cau hinh bai tap tu yeu cau cua Godot."""
        if exercise_id not in self.exercise_states:
            return

        st = self.exercise_states[exercise_id]
        st["movement_state"] = "ready"
        st["current_rep_id"] = ""
        st["completed_reps"] = 0
        st["target_rom_ratio"] = float(config.get("target_rom_ratio", 0.85))
        st["target_side"] = str(config.get("target_side", "both"))
        st["min_movement_duration_ms"] = int(config.get("minimum_movement_duration_ms", 1500))
        st["max_movement_duration_ms"] = int(config.get("maximum_movement_duration_ms", 6000))
        if "hold_duration_ms" in config:
            st["hold_duration_ms"] = int(config["hold_duration_ms"])
        if "calibrated_max_rom" in config and float(config["calibrated_max_rom"]) > 0:
            st["calibrated_max_rom"] = float(config["calibrated_max_rom"])
        if "target_rom_value" in config and float(config["target_rom_value"]) > 0:
            st["target_rom_value"] = float(config["target_rom_value"])

        if exercise_id == "scapular_retraction":
            st["target_rom_ratio"] = max(0.75, min(0.80, float(config.get("target_rom_ratio", 0.78))))
            st["min_movement_duration_ms"] = min(int(config.get("minimum_movement_duration_ms", 500)), 500)
            st["released_below_40"] = False
            st["map1_smoothed_rom"] = 0.0

        if exercise_id == "wall_abduction_external_rotation":
            st["target_rom_ratio"] = min(float(config.get("target_rom_ratio", 0.70)), 0.70)
            st["min_movement_duration_ms"] = min(int(config.get("minimum_movement_duration_ms", 1200)), 1200)

        if exercise_id == "horizontal_shoulder_adduction":
            st["target_rom_ratio"] = min(float(config.get("target_rom_ratio", 0.70)), 0.70)
            st["min_movement_duration_ms"] = min(int(config.get("minimum_movement_duration_ms", 1200)), 1200)

        if exercise_id == "hands_behind_head":
            st["target_rom_ratio"] = min(float(config.get("target_rom_ratio", 0.70)), 0.70)
            st["min_movement_duration_ms"] = min(int(config.get("minimum_movement_duration_ms", 1200)), 1200)

        if exercise_id == "cross_body_shoulder_stretch":
            st["target_rom_ratio"] = min(float(config.get("target_rom_ratio", 0.70)), 0.70)
            st["min_movement_duration_ms"] = min(int(config.get("minimum_movement_duration_ms", 1200)), 1200)
            st["active_stretch_side"] = "none"

        st["last_rom_progress"] = 0.0
        st["last_hold_progress"] = 0.0
        st["peak_rom_achieved"] = 0.0
        st["hold_grace_start_time"] = 0.0
        st["prep_delay_start_time"] = 0.0
        st["prep_hold_start_time"] = 0.0
        self.is_paused = False

    def start_calibration(self, exercise_id: str, duration_ms: int = 5000, target_side: str = "both"):
        """Bat dau qua trinh hieu chuan do ROM toi da."""
        self.calibration_active = True
        self.calib_exercise_id = exercise_id
        self.calib_target_side = target_side
        self.calib_duration_ms = max(duration_ms, 1000)
        self.calib_start_time = time.time()
        self.calib_max_rom_left = 0.0
        self.calib_max_rom_right = 0.0
        self.calib_max_rom_combined = 0.0
        self.calib_last_emit_time = 0.0
        self.filter.reset()

    def stop_calibration(self):
        self.calibration_active = False

    def pause(self):
        self.is_paused = True

    def resume(self):
        self.is_paused = False

    def _next_rep_candidate_id(self, exercise_id: str) -> str:
        st = self.exercise_states[exercise_id]
        st["rep_count"] += 1
        rep_id = f"rep-{exercise_id}-{st['rep_count']:04d}"
        st["current_rep_id"] = rep_id
        return rep_id

    # ==========================
    # KIEM TRA VISIBILITY & POSE STATUS
    # ==========================
    def check_tracking_status(self, landmarks) -> Tuple[bool, str]:
        """
        Kiem tra nguoi choi co dung dung vi tri truoc camera khong.
        Tra ve (is_valid, feedback_code).
        """
        if not landmarks or len(landmarks) < 25:
            return False, "TRACKING_LOST"

        # Kiem tra 2 vai (11, 12) va 2 khuyu tay (13, 14)
        l_sh = landmarks[11]
        r_sh = landmarks[12]
        l_el = landmarks[13]
        r_el = landmarks[14]

        if getattr(l_sh, 'visibility', 1.0) < 0.4 or getattr(r_sh, 'visibility', 1.0) < 0.4:
            return False, "SHOULDERS_NOT_VISIBLE"

        if getattr(l_el, 'visibility', 1.0) < 0.35:
            return False, "LEFT_ARM_NOT_VISIBLE"

        if getattr(r_el, 'visibility', 1.0) < 0.35:
            return False, "RIGHT_ARM_NOT_VISIBLE"

        # Kiem tra khoang cach va do lech tam
        shoulder_dist = self.calculate_2d_distance(l_sh, r_sh)
        center_x = (l_sh.x + r_sh.x) / 2.0

        if shoulder_dist > 0.45:
            return True, "MOVE_BACK"
        if shoulder_dist < 0.12:
            return True, "MOVE_CLOSER"
        if abs(center_x - 0.5) > 0.22:
            return True, "CENTER_YOUR_BODY"

        return True, "POSITION_OK"

    # ==========================
    # TINH TOAN METRICS CHO 5 BAI TAP
    # ==========================
    def _evaluate_map1_scapular_retraction(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """
        Map 1: Ep 2 vai ra sau (Scapular Retraction).
        Kiem soat chat che Y khoa va hinh hoc giai phau:
        - Tu the 1 (Chuan bi / Release): 2 tay vuon/duoi ra truoc huong camera, ROM < 40%.
        - Tu the 2 (Co ba vai / Contract): 2 khuyu tay gap ~90 do va keo lui ra sau mat phang vai/lung.
        - Chuan hoa nhay: Khi nguoi tap ep dung form, ROM de dang dat 100% tron ven, khong bi ket o 86%.
        - Loai tru tuyet doi cac dong tac khac:
          + Khong cho tay gio cao qua vai / qua dau (loai bo Map 2, Map 4).
          + Khong cho 2 khuyu tay dang cao ngang vai (loai bo Map 2, Map 3).
          + Khong cho 2 co tay cham nhau / qua gan (loai bo Map 3).
          + Khong cho 2 khuyu tay dang rong canh ga (loai bo dang tay).
          + Khong cho bat cheo tay qua nguc (loai bo Map 5).
        """
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]
        l_hip, r_hip = lm[23], lm[24]

        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))
        y_sh_avg = (l_sh.y + r_sh.y) / 2.0
        y_hip_avg = (l_hip.y + r_hip.y) / 2.0

        # --- 1. RANG BUOC HINH HOC GIAI PHAU (ANATOMICAL FORM VALIDATION) ---
        # a) Do cao cua tay:
        # Co tay khong gio len tren vai (tranh nhan nham Map 2/4 hoac gio tay len troi)
        hands_not_overhead = (l_wr.y > l_sh.y - 0.08 * shoulder_width) and (r_wr.y > r_sh.y - 0.08 * shoulder_width)
        # Khuong tay phai o phia duoi vai (bap tay xuoi than, khong nhac cao ngang vai nhu Map 2/3)
        elbows_below_shoulders = (l_el.y > l_sh.y + 0.05 * shoulder_width) and (r_el.y > r_sh.y + 0.05 * shoulder_width)
        # Tay khong buong thong qua sau duoi hong
        hands_not_too_low = (l_wr.y < y_hip_avg + 0.25 * shoulder_width) and (r_wr.y < y_hip_avg + 0.25 * shoulder_width)
        elbows_not_too_low = (l_el.y < y_hip_avg + 0.15 * shoulder_width) and (r_el.y < y_hip_avg + 0.15 * shoulder_width)

        # b) Khoang cach ngang va tach biet hai tay (Chong nhan nham Map 3, Map 5, dang tay rong):
        # Khoang cach giua 2 co tay phai tuong duong khoang cach vai (cang tay song song huong ra truoc)
        wrist_dist = self.calculate_2d_distance(l_wr, r_wr)
        wrists_separated = (wrist_dist >= 0.45 * shoulder_width) and (wrist_dist <= 1.60 * shoulder_width)

        # Khoang cach giua 2 khuyu tay khong dang qua rong (chong dang canh ga Map 2/3)
        elbow_dist = self.calculate_2d_distance(l_el, r_el)
        elbows_not_flared = (elbow_dist >= 0.70 * shoulder_width) and (elbow_dist <= 1.60 * shoulder_width)

        # Chong bat cheo tay qua than minh (Map 5 - Cross Body Stretch):
        # Hai co tay phai o hai phia doi xung qua truc giua than minh, khong duoc bat cheo qua nguc
        mid_x = (l_sh.x + r_sh.x) / 2.0
        no_arm_cross = (
            ((l_wr.x - mid_x) * (l_sh.x - mid_x) > 0.02 * (shoulder_width ** 2)) and
            ((r_wr.x - mid_x) * (r_sh.x - mid_x) > 0.02 * (shoulder_width ** 2))
        )

        # c) Goc gap khuyu tay (3D khong bi meo do hieu ung co ngan goc nhin camera):
        ang_l = self.calculate_angle_3d(l_sh, l_el, l_wr)
        ang_r = self.calculate_angle_3d(r_sh, r_el, r_wr)
        avg_elbow_angle = (ang_l + ang_r) / 2.0
        elbow_in_range = (50.0 <= avg_elbow_angle <= 165.0)

        # Tong hop dieu kien form hop le:
        form_valid = (
            hands_not_overhead and
            elbows_below_shoulders and
            hands_not_too_low and
            elbows_not_too_low and
            wrists_separated and
            elbows_not_flared and
            no_arm_cross and
            elbow_in_range
        )

        # --- 2. CAC CHI SO CHUYEN DONG EP BA VAI (RETRACTION METRICS) ---
        # Chi so 1: Goc gap khuyu tay 3D (Elbow Flexion)
        # Dung dong tac nhu hinh: Khuyu tay gap ~90 do (75 - 105 do dat diem cao nhat)
        diff_elbow = abs(avg_elbow_angle - 90.0)
        score_elbow = max(0.0, 1.0 - diff_elbow / 25.0)

        # Chi so 2: Do lui ra sau cua Khuyu tay so voi Vai (Z_elbow - Z_shoulder)
        # Bat buoc 2 khuyu tay phai keo lui ra sau than minh (nhin tu tren xuong o hinh anh y khoa)
        z_el_diff = ((l_el.z - l_sh.z) + (r_el.z - r_sh.z)) / 2.0
        score_z_el = max(0.0, min(1.0, (z_el_diff - (-0.025)) / 0.035))

        # Chi so 3: Do sau Z cua Co tay so voi Vai (Z_wrist - Z_shoulder)
        # Ban tay thu ve ngang nguc/man suon, khong vuon xa ra truoc
        z_wr_diff = ((l_wr.z - l_sh.z) + (r_wr.z - r_sh.z)) / 2.0
        score_z_wr = max(0.0, min(1.0, (z_wr_diff - (-0.15)) / 0.12))

        # Chi so 4: Khoang cach 2D giua co tay va vai (canh tay co gon ve man suon)
        d_l_sh_wr = self.calculate_2d_distance(l_sh, l_wr)
        d_r_sh_wr = self.calculate_2d_distance(r_sh, r_wr)
        avg_wr_sh_dist = (d_l_sh_wr + d_r_sh_wr) / (2.0 * shoulder_width)
        score_wr_dist = max(0.0, min(1.0, (1.10 - avg_wr_sh_dist) / 0.30))

        # --- 3. TINH TIEN DO ROM & CAN CHINH 75% - 80% BIEN DO HIEU CHUAN ---
        if not form_valid:
            combined_score = 0.0
            rom_progress = 0.0
            current_rom_value = 0.0
        else:
            # Hop nhat da chi so voi trong so cao cho do lui cua khuyu va co tay
            combined_score = (
                0.35 * score_z_el +
                0.35 * score_z_wr +
                0.15 * score_elbow +
                0.15 * score_wr_dist
            )
            # Gia tri goc tuong duong (0 - 90 do) de phuc vu Calibration
            current_rom_value = combined_score * 90.0

            calibrated_max = float(self.exercise_states["scapular_retraction"].get("calibrated_max_rom", 0.0))
            calibrated_target = float(self.exercise_states["scapular_retraction"].get("target_rom_value", 0.0))
            target_ratio = float(self.exercise_states["scapular_retraction"].get("target_rom_ratio", 0.78))
            # Dam bao ty le muc tieu nam trong khoang 75% - 80% bien do toi da
            target_ratio = max(0.75, min(0.80, target_ratio))

            if calibrated_max > 15.0:
                target_rom_deg = calibrated_max * target_ratio
            elif calibrated_target > 15.0:
                target_rom_deg = calibrated_target
            else:
                # Neu chua calib: 78% cua 90 do tieu chuan y khoa = 70.2 do
                target_rom_deg = 90.0 * target_ratio

            raw_rom = current_rom_value / target_rom_deg
            # Dat tu 95% tro len cua muc tieu (75-80% max) la hoan thanh 100% ROM
            if raw_rom >= 0.95:
                rom_progress = 1.0
            else:
                rom_progress = max(0.0, raw_rom / 0.95)

        return {
            "angles": {
                "elbow_angle": round(avg_elbow_angle, 1),
                "wrist_z_diff": round(z_wr_diff, 3),
                "elbow_z_diff": round(z_el_diff, 3),
                "wrist_dist": round(wrist_dist / shoulder_width, 2),
                "elbow_dist": round(elbow_dist / shoulder_width, 2),
                "combined_score": round(combined_score, 2),
                "current_rom_value": round(current_rom_value, 1),
            },
            "form_valid": form_valid,
            "rom_progress": round(rom_progress, 3),
            "current_rom_value": current_rom_value,
            "target_depth": 0.05,
        }

    def _evaluate_map2_wall_abduction(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """
        Map 2: Dang va xoay ngoai khop vai o tu the dung ap sat tuong (Wall Slide / Wall Abduction), giu 5s.
        Giai doan 1: Tu the chuan bi (Hinh 1) - Canh tay dang ngang ~90 do, cang tay gap ~90 do huong len (chu U / W).
        Giai doan 2: Dong tac tap va giu (Hinh 2) - 2 tay truot vuon thang len cao tren dau, giu 5 giay.
        """
        l_hip, r_hip = lm[23], lm[24]
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))

        # --- 1. TINH TOAN METRICS CHO TU THE CHUAN BI (HINH 1: CHU U VUONG GOC) ---
        # a) Goc dang canh tay so voi than (Hong - Vai - Khuyu)
        l_sh_angle = self.calculate_angle(l_hip, l_sh, l_el)
        r_sh_angle = self.calculate_angle(r_hip, r_sh, r_el)
        avg_sh_angle = (l_sh_angle + r_sh_angle) / 2.0

        # b) Goc gap khuyu tay (Vai - Khuyu - Co tay)
        l_el_angle = self.calculate_angle(l_sh, l_el, l_wr)
        r_el_angle = self.calculate_angle(r_sh, r_el, r_wr)
        avg_el_angle = (l_el_angle + r_el_angle) / 2.0

        # c) Co tay huong len (cao hon hoac ngang bang khuyu tay tren truc Y)
        wrists_above_elbows = (l_wr.y <= l_el.y + 0.02 * shoulder_width) and (r_wr.y <= r_el.y + 0.02 * shoulder_width)

        # d) Do rong hai khuyu tay (khuyu dang ngang vai)
        elbow_dist = self.calculate_2d_distance(l_el, r_el)
        elbow_wide = elbow_dist >= 0.95 * shoulder_width

        # Diem goc vai gan 90 do (70 - 110 do dat diem cao)
        diff_sh = abs(avg_sh_angle - 90.0)
        score_sh = max(0.0, 1.0 - diff_sh / 35.0)

        # Diem goc khuyu gan 90 do (65 - 115 do dat diem cao)
        diff_el = abs(avg_el_angle - 90.0)
        score_el = max(0.0, 1.0 - diff_el / 35.0)

        score_upright = 1.0 if wrists_above_elbows else 0.4
        score_wide = 1.0 if elbow_wide else 0.5

        prep_score = (
            0.35 * score_sh +
            0.35 * score_el +
            0.15 * score_upright +
            0.15 * score_wide
        )
        is_prep_pose = (
            (prep_score >= 0.75) and
            wrists_above_elbows and
            (70.0 <= avg_el_angle <= 110.0) and
            (70.0 <= avg_sh_angle <= 110.0) and
            (elbow_dist >= 1.05 * shoulder_width) and
            (self.calculate_2d_distance(l_wr, r_wr) >= 0.75 * shoulder_width)
        )

        # --- 2. TINH TOAN METRICS CHO DONG TAC VUON CAO VA GIU (HINH 2: 2 TAY GIO CAO TREN DAU) ---
        # a) Do cao vuon len cua co tay va khuyu tay so voi vai (chuan hoa theo chieu rong vai)
        l_wrist_reach = (l_sh.y - l_wr.y) / shoulder_width
        r_wrist_reach = (r_sh.y - r_wr.y) / shoulder_width
        avg_wrist_reach = (l_wrist_reach + r_wrist_reach) / 2.0

        l_elbow_reach = (l_sh.y - l_el.y) / shoulder_width
        r_elbow_reach = (r_sh.y - r_el.y) / shoulder_width
        avg_elbow_reach = (l_elbow_reach + r_elbow_reach) / 2.0

        reach_score = 0.65 * avg_wrist_reach + 0.35 * avg_elbow_reach

        # Tinh tien do ROM cho tung goc cu dong trong Hinh 2:
        # a) Goc nang vai vuon len cao (Hinh 1: ~90 do -> Hinh 2: >= 140 do)
        rom_sh = max(0.0, min(1.0, (avg_sh_angle - 100.0) / 45.0))

        # b) Goc duoi khuyu tay vuon doc tuong (Hinh 1: ~90 do -> Hinh 2: >= 140 do)
        rom_el = max(0.0, min(1.0, (avg_el_angle - 105.0) / 40.0))

        # c) Do nang khuyu tay vuot len khoi vai (Hinh 1: khuyu ngang vai -> Hinh 2: khuyu nang cao)
        rom_el_reach = max(0.0, min(1.0, (avg_elbow_reach - 0.15) / 0.28))

        # d) Do vuon co tay qua dinh dau (Hinh 1: wrist_reach ~ 0.75 -> Hinh 2: wrist_reach >= 1.15)
        rom_wr_reach = max(0.0, min(1.0, (avg_wrist_reach - 0.95) / 0.35))

        # Tien do ROM tong hop cua Hinh 2:
        raw_hold_rom = (
            0.35 * rom_sh +
            0.35 * rom_el +
            0.20 * rom_el_reach +
            0.10 * rom_wr_reach
        )

        # LOAI TRU TUYET DOI HINH 1 VA DONG TAC KHAC (CHONG NHAN NHAM):
        # Neu nguoi choi van o the chu U vuong goc (is_prep_pose)
        # HOAC khuyu tay chua duoi (< 120 do)
        # HOAC vai chua nang cao (< 125 do)
        # HOAC co tay chua vuon cao qua dau (avg_wrist_reach < 0.95):
        # -> hold_rom TRIET DE BANG 0.0 va is_hold_pose = False!
        if is_prep_pose or (avg_el_angle < 120.0) or (avg_sh_angle < 125.0) or (avg_wrist_reach < 0.95):
            hold_rom = 0.0
            is_hold_pose = False
        else:
            hold_rom = raw_hold_rom
            # Chi ghi nhan dat the Hinh 2 khi:
            # - Khop vai da nang cao >= 130 do
            # - Khuyu tay da duoi vuon >= 120 do
            # - Khuyu tay da nang cao hon vai (avg_elbow_reach >= 0.22)
            # - Co tay vuon cao qua dinh dau (avg_wrist_reach >= 1.0)
            # - Tien do hold_rom dat tu 0.75 tro len
            is_hold_pose = (
                (avg_sh_angle >= 130.0) and
                (avg_el_angle >= 120.0) and
                (avg_elbow_reach >= 0.22) and
                (avg_wrist_reach >= 1.0) and
                (hold_rom >= 0.75)
            )

        # Form hop le co ban: co tay khong bi roi xuong duoi vai
        form_valid = (l_wr.y < l_sh.y) and (r_wr.y < r_sh.y)

        current_rom_value = round(avg_sh_angle, 1)

        return {
            "angles": {
                "prep_score": round(prep_score, 2),
                "is_prep_pose": is_prep_pose,
                "reach_score": round(reach_score, 2),
                "avg_wrist_reach": round(avg_wrist_reach, 2),
                "avg_elbow_reach": round(avg_elbow_reach, 2),
                "avg_sh_angle": round(avg_sh_angle, 1),
                "avg_el_angle": round(avg_el_angle, 1),
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": hold_rom,
            "prep_score": prep_score,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "reach_score": reach_score,
            "current_rom_value": current_rom_value,
            "target_angle": 135.0,
        }

    def _evaluate_map3_horizontal_shoulder_adduction(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """
        Map 3: Khep ngang khop vai / Dang mo nguc 2 ben (Horizontal Shoulder Adduction), giu 5s.
        Dong tac Y khoa:
        - The chuan bi (Hinh 1): Khep 2 khuyu tay va 2 ban tay up sat vao nhau truoc nguc/mat.
        - The giu (Hinh 2): Tu tu dang 2 canh tay mo rong sang 2 ben (van giu khuyu vuong goc vai,
          cang tay huong len tren), giu 5 giay.
        """
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]
        l_hip, r_hip = lm[23], lm[24]

        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))
        elbow_dist = self.calculate_2d_distance(l_el, r_el)
        wrist_dist = self.calculate_2d_distance(l_wr, r_wr)

        elbow_ratio = elbow_dist / shoulder_width
        wrist_ratio = wrist_dist / shoulder_width

        # 1. Kiem tra huong cang tay huong len tren (Forearms Upright)
        # Co tay cao hon khuyu tay (y nho hon tren he toa do anh)
        wrists_above_elbows = (l_wr.y <= l_el.y + 0.15 * shoulder_width) and (r_wr.y <= r_el.y + 0.15 * shoulder_width)

        # 2. Kiem tra do cao khuyu tay (Elbows Elevated)
        # Khuyu tay khong bi ha xuong duoi bung/hong (y khuyu khong thap hon vai qua 0.55 chieu rong vai)
        elbows_elevated = ((l_el.y - l_sh.y) <= 0.55 * shoulder_width) and ((r_el.y - r_sh.y) <= 0.55 * shoulder_width)

        # 3. Goc gap khuyu tay
        l_elbow_angle = self.calculate_angle(l_sh, l_el, l_wr)
        r_elbow_angle = self.calculate_angle(r_sh, r_el, r_wr)
        avg_el_angle = (l_elbow_angle + r_elbow_angle) / 2.0

        # --- A. METRICS CHO THE CHUAN BI (HINH 1: KHEP 2 KHUYU TAY & BAN TAY TRUOC NGUC) ---
        # Khi khep sat: elbow_ratio ~ 0.35 - 0.65, wrist_ratio ~ 0.30 - 0.60
        # Nguong mo rong thuc te phu hop voi kich thuoc co the nguoi that:
        close_el_score = max(0.0, min(1.0, (0.85 - elbow_ratio) / (0.85 - 0.50)))
        close_wr_score = max(0.0, min(1.0, (0.82 - wrist_ratio) / (0.82 - 0.42)))
        upright_score = 1.0 if wrists_above_elbows else 0.4

        prep_score = (
            0.45 * close_el_score +
            0.45 * close_wr_score +
            0.10 * upright_score
        )
        is_prep_pose = (prep_score >= 0.55) and (elbow_ratio <= 0.72) and (wrist_ratio <= 0.70) and wrists_above_elbows and elbows_elevated

        # --- B. METRICS CHO THE GIU 5S (HINH 2: DANG 2 CANH TAY SANG 2 BEN) ---
        # Khi dang rong 2 ben: elbow_ratio ~ 1.20 - 1.80, wrist_ratio ~ 1.10 - 1.80
        open_el_score = max(0.0, min(1.0, (elbow_ratio - 0.85) / (1.25 - 0.85)))
        open_wr_score = max(0.0, min(1.0, (wrist_ratio - 0.80) / (1.20 - 0.80)))

        chest_open_score = 0.55 * elbow_ratio + 0.45 * wrist_ratio
        raw_hold_rom = (
            0.50 * open_el_score +
            0.50 * open_wr_score
        )

        # Kiem tra khong duoi thang tay nhu Map 2 (khuyu phai giu vuong goc 70 - 115 do)
        # va khong vuon tay cao qua dau nhu Map 2
        not_reaching_overhead = ((l_sh.y - l_wr.y) / shoulder_width <= 0.95) and ((r_sh.y - r_wr.y) / shoulder_width <= 0.95)
        elbows_bent_properly = (70.0 <= avg_el_angle <= 115.0)

        form_valid = wrists_above_elbows and elbows_elevated and not_reaching_overhead and elbows_bent_properly

        # CHONG NHAN NHAM HINH 1 HOAC MAP KHAC:
        # Neu nguoi choi van dang khep tay o the Hinh 1 (is_prep_pose), hoac chua mo rong (elbow_ratio < 0.90),
        # hoac vuon tay qua dau / duoi thang tay (not form_valid):
        # hold_rom TRIET DE BANG 0.0 va is_hold_pose = False!
        if is_prep_pose or (elbow_ratio < 0.90) or (wrist_ratio < 0.85) or (not form_valid):
            hold_rom = 0.0
            is_hold_pose = False
        else:
            hold_rom = raw_hold_rom
            # Ghi nhan the Hinh 2 khi:
            # 1. Khuyu tay va co tay da dang rong sang 2 ben ro ret
            # 2. Canh tay van vuong goc huong len tren, khong vuon qua dau
            # 3. Tien do hold_rom dat tu 0.75 tro len
            is_hold_pose = (
                (elbow_ratio >= 1.20) and
                (wrist_ratio >= 1.10) and
                (hold_rom >= 0.75) and
                form_valid
            )

        return {
            "angles": {
                "prep_score": round(prep_score, 2),
                "is_prep_pose": is_prep_pose,
                "chest_open_score": round(chest_open_score, 2),
                "elbow_ratio": round(elbow_ratio, 2),
                "wrist_ratio": round(wrist_ratio, 2),
                "avg_el_angle": round(avg_el_angle, 1),
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": hold_rom,
            "prep_score": prep_score,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "current_rom_value": round(chest_open_score * 50.0, 1),
            "target_ratio": 1.25,
        }

    def _evaluate_map4_hands_behind_head(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """
        Map 4: Van dong khop vai o tu the 2 tay om dau (Hands behind head / Khep mo khuyu tay)
        Theo kich ban va hinh anh:
        - Hinh 1 (Chuan bi): Canh tay dang sang 2 ben huong len tren, 2 ban tay dat sau dau / sau gay.
        - Hinh 2 (Giu 5 giay): Tu tu khep 2 canh tay ve phia truoc (2 khuyu tay khep sat vao nhau truoc mat, giu tay sau dau).
        """
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))
        elbow_dist = self.calculate_2d_distance(l_el, r_el)
        wrist_dist = self.calculate_2d_distance(l_wr, r_wr)

        elbow_ratio = elbow_dist / shoulder_width
        wrist_ratio = wrist_dist / shoulder_width

        y_sh_avg = (l_sh.y + r_sh.y) / 2.0
        y_el_avg = (l_el.y + r_el.y) / 2.0

        st_map4 = self.exercise_states.get("hands_behind_head", {})
        curr_state = st_map4.get("movement_state", "ready")

        # 1. Kiem tra 2 ban tay o vung dau / co / tren vai:
        hands_raised = (l_wr.y <= l_sh.y + 0.45 * shoulder_width) and (r_wr.y <= r_sh.y + 0.45 * shoulder_width)

        # 2. Kiem tra do cao khuyu tay (Elbows Elevated):
        elbows_elevated = (y_el_avg <= y_sh_avg + 0.55 * shoulder_width)

        # Form hop le:
        # Khi dang o the giu (holding) hoac closing: co the wrists bi dau va cang tay che khuat
        if curr_state in ["closing", "holding"]:
            form_valid = elbows_elevated and (elbow_ratio <= 1.25)
        else:
            form_valid = hands_raised and elbows_elevated

        # --- A. METRICS CHO THE CHUAN BI (HINH 1: 2 TAY OM DAU, MO RONG KHUYU SANG 2 BEN) ---
        open_el_score = max(0.0, min(1.0, (elbow_ratio - 1.05) / (1.40 - 1.05)))
        prep_score = open_el_score if (hands_raised and elbows_elevated) else 0.0
        is_prep_pose = (elbow_ratio >= 1.15) and hands_raised and elbows_elevated

        # --- B. METRICS CHO THE GIU 5S (HINH 2: KHEP 2 KHUYU TAY VE PHIA TRUOC MAT) ---
        # Thang do tuyen tinh muot ma cho viec khep khuyu tay:
        # elbow_ratio <= 1.00 -> 100%
        # elbow_ratio = 1.15 -> 40%
        # elbow_ratio >= 1.25 -> 0%
        close_el_score = max(0.0, min(1.0, (1.25 - elbow_ratio) / (1.25 - 1.00)))

        # Xu ly rieng de DAM BAO KHONG BAO GIO GIAT ROM VE 0 KHI DANG HOLDING:
        if curr_state == "holding":
            # Khi dang giu:
            # Neu nguoi choi van duy tri the khep truoc mat (elbow_ratio <= 1.15):
            # ROM BAT BUOC luon >= 0.40 va is_hold_pose luon True!
            if elbow_ratio <= 1.15 and elbows_elevated:
                hold_rom = max(0.40, close_el_score)
                is_hold_pose = True
                form_valid = True
            elif elbow_ratio <= 1.25 and elbows_elevated:
                hold_rom = close_el_score
                is_hold_pose = False
                form_valid = True
            else:
                hold_rom = 0.0
                is_hold_pose = False
                form_valid = False
        else:
            if is_prep_pose or (elbow_ratio >= 1.20) or (not form_valid):
                hold_rom = 0.0
                is_hold_pose = False
            else:
                hold_rom = close_el_score
                is_hold_pose = (
                    (elbow_ratio <= 1.05) and
                    (hold_rom >= 0.75) and
                    form_valid
                )

        return {
            "angles": {
                "prep_score": round(prep_score, 2),
                "is_prep_pose": is_prep_pose,
                "close_el_score": round(close_el_score, 2),
                "elbow_ratio": round(elbow_ratio, 2),
                "wrist_ratio": round(wrist_ratio, 2),
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": hold_rom,
            "prep_score": prep_score,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "current_rom_value": round(close_el_score * 60.0, 1),
            "target_ratio": 0.60,
        }

    def _evaluate_map5_cross_body_stretch(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """
        Map 5: Keo cang canh tay qua nguc (Cross-body Shoulder Stretch), giu 30s.
        Dung tay ben nay keo canh tay ben kia qua ngang nguc, giu lai bang cach kep giua cang tay va thanh nguc.
        """
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))
        shoulder_y = (l_sh.y + r_sh.y) / 2.0
        
        # Hip landmarks neu co de xac dinh do cao vung than tren
        hip_y = shoulder_y + 1.2 * shoulder_width
        if len(lm) > 24 and getattr(lm[23], 'visibility', 1.0) > 0.3 and getattr(lm[24], 'visibility', 1.0) > 0.3:
            hip_y = (lm[23].y + lm[24].y) / 2.0

        # 1. Do ben phai (keo canh tay PHAI qua ngang nguc sang ben TRAI)
        r_stretch_dist = self.calculate_2d_distance(r_wr, l_sh)
        r_elbow_angle = self.calculate_angle(r_sh, r_el, r_wr)
        # Kiem tra ca 2 tay deu o vung than tren/nguc (khong buong thong xuong hong)
        r_height_ok = (r_wr.y < hip_y - 0.05 * shoulder_width) and (r_el.y < hip_y - 0.05 * shoulder_width)
        # Cung cap do linh hoat goc khuyu de chong nhieu perspective va chong MediaPipe rung
        r_form_valid = r_height_ok and (r_elbow_angle >= 70.0)

        # 2. Do ben trai (keo canh tay TRAI qua ngang nguc sang ben PHAI)
        l_stretch_dist = self.calculate_2d_distance(l_wr, r_sh)
        l_elbow_angle = self.calculate_angle(l_sh, l_el, l_wr)
        l_height_ok = (l_wr.y < hip_y - 0.05 * shoulder_width) and (l_el.y < hip_y - 0.05 * shoulder_width)
        l_form_valid = l_height_ok and (l_elbow_angle >= 70.0)

        # Tinh ROM cho tung ben:
        # Khi chua keo: khoang cach ~ 0.95 - 1.2 * shoulder_width
        # Khi keo qua nguc tot: khoang cach <= 0.65 * shoulder_width
        r_rom_raw = max(0.0, min(1.0, (0.95 * shoulder_width - r_stretch_dist) / (0.95 * shoulder_width - 0.65 * shoulder_width)))
        l_rom_raw = max(0.0, min(1.0, (0.95 * shoulder_width - l_stretch_dist) / (0.95 * shoulder_width - 0.65 * shoulder_width)))

        st = self.exercise_states["cross_body_shoulder_stretch"]
        target_side = st.get("target_side", "both")
        active_side = st.get("active_stretch_side", "none")
        current_state = st.get("movement_state", "ready")

        # Khoa ben khi dang tap (contracting hoac holding) de chong hien tuong nhay ben lam giat % ROM
        if current_state in ["contracting", "holding"] and active_side in ["left", "right"]:
            chosen_side = active_side
        elif target_side == "left":
            chosen_side = "left"
        elif target_side == "right":
            chosen_side = "right"
        else:
            # Tu dong chon ben dang keo ro rang hon
            if r_rom_raw > l_rom_raw and r_rom_raw >= 0.25:
                chosen_side = "right"
            elif l_rom_raw > r_rom_raw and l_rom_raw >= 0.25:
                chosen_side = "left"
            else:
                chosen_side = "right" if r_rom_raw >= l_rom_raw else "left"

        if chosen_side == "right":
            active_dist = r_stretch_dist
            raw_form_valid = r_form_valid
            active_raw_rom = r_rom_raw
            elbow_angle = r_elbow_angle
        else:
            active_dist = l_stretch_dist
            raw_form_valid = l_form_valid
            active_raw_rom = l_rom_raw
            elbow_angle = l_elbow_angle

        # Peak Latch: theo doi moc tien do keo cao nhat de chong rung lui % khi keo
        if "peak_stretch_rom" not in st:
            st["peak_stretch_rom"] = 0.0

        if current_state == "holding":
            # Trong suot thoi gian HOLDING 30s:
            # Khoa san ROM 100% tuyet doi, form luon hop le neu hai tay van o vung than tren nguc
            is_released = (active_dist > 0.85 * shoulder_width) or (r_wr.y > hip_y and l_wr.y > hip_y)
            form_valid = not is_released
            rom_progress = 1.0
        elif current_state == "contracting":
            if active_raw_rom > st["peak_stretch_rom"]:
                st["peak_stretch_rom"] = active_raw_rom
            elif active_raw_rom < st["peak_stretch_rom"] - 0.20:
                st["peak_stretch_rom"] = max(active_raw_rom, st["peak_stretch_rom"] - 0.03)

            effective_rom = max(active_raw_rom, st["peak_stretch_rom"])
            # Khi dat tu 70% tro len va form hop le: Boost ngay 100% de nguoi choi vao the de dang
            if (effective_rom >= 0.70 or active_raw_rom >= 0.70) and raw_form_valid:
                rom_progress = 1.0
            else:
                rom_progress = effective_rom
            form_valid = raw_form_valid
        else:
            # ready / returning
            st["peak_stretch_rom"] = 0.0
            rom_progress = active_raw_rom
            form_valid = raw_form_valid

        # Cap nhat active_side neu bat dau vao the
        if rom_progress >= 0.25 and current_state in ["ready", "contracting"]:
            st["active_stretch_side"] = chosen_side

        return {
            "angles": {
                "stretch_distance": round(active_dist, 2),
                "shoulder_width": round(shoulder_width, 2),
                "left_elbow_angle": round(l_elbow_angle, 1),
                "right_elbow_angle": round(r_elbow_angle, 1),
                "active_side": chosen_side,
                "raw_rom": round(active_raw_rom, 2),
            },
            "form_valid": form_valid,
            "rom_progress": rom_progress,
            "current_rom_value": rom_progress * 90.0,
            "target_dist": 0.65 * shoulder_width,
            "active_side": chosen_side,
        }

    # ==========================
    # XU LY CALIBRATION (DO ROM)
    # ==========================
    def process_calibration(self, raw_landmarks) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        """
        Xu ly do ROM theo thoi gian thuc.
        Tra ve: (calibration_progress_payload, calibration_completed_payload)
        """
        if not self.calibration_active:
            return None, None

        lm = self.filter.filter(raw_landmarks)
        is_tracking_ok, feedback = self.check_tracking_status(lm)

        now = time.time()
        elapsed_ms = int((now - self.calib_start_time) * 1000)
        progress = min(1.0, elapsed_ms / float(self.calib_duration_ms))

        # Tinh ROM hien tai tuy theo bai tap duoc calib
        current_val = 0.0
        if is_tracking_ok:
            if self.calib_exercise_id == "scapular_retraction":
                m = self._evaluate_map1_scapular_retraction(lm)
                current_val = m["current_rom_value"]
            elif self.calib_exercise_id == "wall_abduction_external_rotation":
                m = self._evaluate_map2_wall_abduction(lm)
                current_val = m["current_rom_value"]
            elif self.calib_exercise_id == "horizontal_shoulder_adduction":
                m = self._evaluate_map3_horizontal_shoulder_adduction(lm)
                current_val = m["current_rom_value"]
            elif self.calib_exercise_id == "hands_behind_head":
                m = self._evaluate_map4_hands_behind_head(lm)
                current_val = m["current_rom_value"]
            elif self.calib_exercise_id == "cross_body_shoulder_stretch":
                m = self._evaluate_map5_cross_body_stretch(lm)
                current_val = m["current_rom_value"]

            # Cap nhat dinh ROM toi da
            self.calib_max_rom_combined = max(self.calib_max_rom_combined, current_val)
            self.calib_max_rom_left = max(self.calib_max_rom_left, current_val)
            self.calib_max_rom_right = max(self.calib_max_rom_right, current_val)

        # Tao event calibration_progress dinh ky (moi 250ms)
        progress_msg = None
        if now - self.calib_last_emit_time >= 0.25:
            self.calib_last_emit_time = now
            progress_msg = {
                "exercise_id": self.calib_exercise_id,
                "progress": round(progress, 2),
                "elapsed_ms": elapsed_ms,
                "duration_ms": self.calib_duration_ms,
                "tracking_valid": is_tracking_ok,
                "current_rom_value": round(current_val, 1),
                "rom_unit": "degree",
                "feedback_code": "KEEP_POSITION" if is_tracking_ok else feedback,
            }

        # Hoan tat calibration
        completed_msg = None
        if progress >= 1.0:
            self.calibration_active = False
            rec_ratio = 0.85
            rec_target = round(self.calib_max_rom_combined * rec_ratio, 2)

            # Luu vao state de bai tap dung luon
            if self.calib_exercise_id in self.exercise_states:
                self.exercise_states[self.calib_exercise_id]["calibrated_max_rom"] = self.calib_max_rom_combined
                self.exercise_states[self.calib_exercise_id]["target_rom_value"] = rec_target

            completed_msg = {
                "exercise_id": self.calib_exercise_id,
                "success": bool(self.calib_max_rom_combined > 5.0),
                "target_side": self.calib_target_side,
                "max_rom": {
                    "left": round(self.calib_max_rom_left, 1),
                    "right": round(self.calib_max_rom_right, 1),
                    "combined": round(self.calib_max_rom_combined, 1),
                    "unit": "degree",
                },
                "confidence": 0.95 if is_tracking_ok else 0.40,
                "recommended_target_ratio": rec_ratio,
                "recommended_target_value": rec_target,
                "feedback_code": "CALIBRATION_COMPLETED" if self.calib_max_rom_combined > 5.0 else "CALIBRATION_LOW_CONFIDENCE",
            }

        return progress_msg, completed_msg

    # ==========================
    # MAY TRANG THAI PHIEN TAP CHINH (EXERCISE STATE MACHINE)
    # ==========================
    def process_frame(self, exercise_id: str, raw_landmarks) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
        """
        Ham trung tam: Danh gia pose hien tai, cap nhat state machine,
        va sinh cac su kien rep_completed, hold_progress, rep_rejected...
        Tra ve: (pose_metrics, list_of_events)
        """
        events: List[Dict[str, Any]] = []

        if exercise_id not in self.exercise_states or not raw_landmarks:
            return {}, events

        st = self.exercise_states[exercise_id]
        if self.is_paused and exercise_id != "scapular_retraction":
            return {
                "angles": {},
                "exercise": {
                    "exercise_id": exercise_id,
                    "movement_state": "paused",
                    "form_valid": True,
                    "rom_progress": 0.0,
                    "hold_progress": 0.0,
                    "movement_duration_ms": 0,
                    "quality": 0.0,
                    "feedback_code": "POSITION_OK",
                },
            }, events

        # Loc nhieu qua EMA
        lm = self.filter.filter(raw_landmarks)
        is_tracking_ok, feedback = self.check_tracking_status(lm)

        # 1. Tinh metrics cu the cho tung bai
        if exercise_id == "scapular_retraction":
            eval_data = self._evaluate_map1_scapular_retraction(lm)
        elif exercise_id == "wall_abduction_external_rotation":
            eval_data = self._evaluate_map2_wall_abduction(lm)
        elif exercise_id == "horizontal_shoulder_adduction":
            eval_data = self._evaluate_map3_horizontal_shoulder_adduction(lm)
        elif exercise_id == "hands_behind_head":
            eval_data = self._evaluate_map4_hands_behind_head(lm)
        elif exercise_id == "cross_body_shoulder_stretch":
            eval_data = self._evaluate_map5_cross_body_stretch(lm)
        else:
            return {}, events

        now = time.time()
        rom_prog = eval_data.get("rom_progress", 0.0)
        form_valid = eval_data["form_valid"] and is_tracking_ok
        st["peak_rom_achieved"] = max(st["peak_rom_achieved"], rom_prog)

        hold_duration_ms = st["hold_duration_ms"]
        is_hold_exercise = hold_duration_ms > 0

        current_state = st["movement_state"]
        feedback_code = feedback if not is_tracking_ok else ("POSITION_OK" if form_valid else "TARGET_NOT_REACHED")
        hold_prog = 0.0

        # 2. May trang thai cu dong (State Machine)
        if exercise_id == "scapular_retraction":
            # ==========================================
            # MAP 1: EP 2 BA VAI RA SAU (SCAPULAR RETRACTION)
            # CO CHE: CHUAN BI -> CO EP -> GIU CO CO TINH (0.7s) -> CHEM DA -> NHA (< 40%)
            # ==========================================

            # Loc EMA rieng cho ROM Map 1 giup triet tieu rung giat va loai bo hien tuong nhay vot so lieu
            if "map1_smoothed_rom" not in st:
                st["map1_smoothed_rom"] = 0.0
            st["map1_smoothed_rom"] = 0.28 * rom_prog + 0.72 * st["map1_smoothed_rom"]
            rom_effective = round(st["map1_smoothed_rom"], 3)
            eval_data["rom_progress"] = rom_effective

            # Thoi gian bat buoc giu co co tinh: 700ms (0.7s, trong khoang 0.5s - 1.0s theo yeu cau)
            config_hold = int(st.get("hold_duration_ms", 700))
            HOLD_TARGET_MS = config_hold if (500 <= config_hold <= 1000) else 700

            # Neu dang paused (vi du: dang cho tang da lan den vung chem):
            # Van tiep tuc cap nhat trang thai releasing -> ready de nguoi choi san sang,
            # nhung KHONG phat sinh su kien rep_completed / chem da som khi da chua toi.
            if self.is_paused:
                if rom_effective < 0.40:
                    st["released_below_40"] = True
                    if current_state in ("returning", "holding"):
                        st["movement_state"] = "ready"
                feedback_code = "ROCK_APPROACHING" if st.get("released_below_40", False) else "RELEASE_POSITION"
                return {
                    "angles": eval_data.get("angles", {}),
                    "exercise": {
                        "exercise_id": exercise_id,
                        "movement_state": st["movement_state"],
                        "form_valid": form_valid,
                        "rom_progress": rom_effective,
                        "hold_progress": 0.0,
                        "movement_duration_ms": 0,
                        "quality": 0.95 if form_valid else 0.30,
                        "feedback_code": feedback_code,
                    },
                }, events

            # --- TRANG THAI 1: READY (CHUAN BI SAN SANG) ---
            if current_state == "ready":
                # Dieu kien tien quyet: Bat buoc nguoi choi phai tung ha ROM ve duoi 40%
                if not st.get("released_below_40", False):
                    if rom_effective < 0.40:
                        st["released_below_40"] = True
                        feedback_code = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"
                    else:
                        feedback_code = "RELEASE_POSITION"
                else:
                    feedback_code = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"

                    # Nguoi choi bat dau co ep hai ba vai tu the tha long:
                    # ROM bat dau vuot nguong 0.40 va form dung
                    if rom_effective >= 0.40 and form_valid:
                        st["movement_state"] = "contracting"
                        st["movement_start_time"] = now
                        st["peak_rom_achieved"] = rom_effective
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "quality": 0.85,
                            "feedback_code": "MOVEMENT_STARTED",
                        })
                        feedback_code = "CONTINUE_MOVEMENT"

            # --- TRANG THAI 2: CONTRACTING (DANG CO EP BA VAI) ---
            elif current_state == "contracting":
                feedback_code = "CONTINUE_MOVEMENT"
                st["peak_rom_achieved"] = max(st["peak_rom_achieved"], rom_effective)
                movement_duration_ms = int((now - st["movement_start_time"]) * 1000)

                # Khi ROM dat dinh (>= 0.95) va form dung chuan:
                if rom_effective >= 0.95 and form_valid:
                    # Kiem tra neu vung tay giat cuc qua nhanh (< 350ms):
                    if movement_duration_ms < 350:
                        feedback_code = "MOVEMENT_TOO_FAST"
                        events.append({
                            "event": "movement_too_fast",
                            "rep_candidate_id": st["current_rep_id"],
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })

                    # Chuyen sang giai doan GIU CO CO TINH (HOLDING 700ms)
                    st["movement_state"] = "holding"
                    st["hold_start_time"] = now
                    st["last_hold_emit_time"] = now
                    events.append({
                        "event": "target_reached",
                        "rep_candidate_id": st["current_rep_id"],
                        "quality": 0.95,
                        "feedback_code": "TARGET_REACHED",
                    })
                    feedback_code = "KEEP_POSITION"

                elif rom_effective < 0.25:
                    # Nguoi choi buong tay som khi chua dat dinh ROM
                    st["movement_state"] = "ready"
                    st["released_below_40"] = True
                    feedback_code = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"

            # --- TRANG THAI 3: HOLDING (GIU TU THE EP BA VAI 0.5s - 1.0s, CHUAN 700ms) ---
            elif current_state == "holding":
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(HOLD_TARGET_MS))

                # Neu nguoi choi buong tay som truoc khi du 700ms (ROM tut xuong < 0.75 hoac sai form):
                if (rom_effective < 0.75) or (not form_valid):
                    # Neu buong qua nhanh (vung tay roi tha ngay < 500ms):
                    if hold_elapsed_ms < 500:
                        feedback_code = "MOVEMENT_TOO_FAST"
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": st["current_rep_id"],
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.40,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                    else:
                        feedback_code = "TARGET_NOT_REACHED"

                    # Kiem tra neu buong han ve duoi 40%:
                    if rom_effective < 0.40:
                        st["released_below_40"] = True
                        st["movement_state"] = "ready"
                    else:
                        st["released_below_40"] = False
                        st["movement_state"] = "returning"

                else:
                    # Nguoi choi dang duy tri the ep tot:
                    feedback_code = "KEEP_POSITION"

                    # KHI DA GIU DU 700ms (>= 1.0):
                    # NGAY LAP TUC phat rep_completed de nhan vat chem da tuc thi!
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)

                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": HOLD_TARGET_MS,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.98,
                            "feedback_code": "REP_VALID",
                        })

                        # KHOA TRANG THAI CHUYEN SANG "returning" (RELEASE LOCKOUT)
                        # BAT BUOC NGUOI CHOI PHAI NHA TAY VE TRUOC (ROM < 40%) MOI MO KHOA
                        st["movement_state"] = "returning"
                        st["released_below_40"] = False
                        st["peak_rom_achieved"] = 0.0
                        feedback_code = "RELEASE_POSITION"

            # --- TRANG THAI 4: RETURNING (CHO NHA CO VE TRUOC < 40%) ---
            elif current_state == "returning":
                feedback_code = "RELEASE_POSITION"

                # DIEU KIEN TIEN QUYET: CHI KHI ROM TUT VE DUOI 40% (0.40)
                # MOI DUOC MO KHOA CHUYEN SANG "ready" VA SET released_below_40 = True
                if rom_effective < 0.40:
                    st["released_below_40"] = True
                    st["movement_state"] = "ready"
                    feedback_code = "READY_FOR_NEXT_REP"

        elif exercise_id == "wall_abduction_external_rotation":
            # ==========================================
            # MAP 2: DANG VA XOAY NGOAI KHOP VAI (WALL SLIDE)
            # QUY TRINH 2 GIAI DOAN: CHUAN BI (HINH 1) -> DELAY 3S -> GIU 5S (HINH 2)
            # ==========================================
            prep_score = eval_data["prep_score"]
            is_prep_pose = eval_data["is_prep_pose"]
            hold_rom = eval_data["hold_rom"]
            is_hold_pose = eval_data["is_hold_pose"]
            reach_score = eval_data["reach_score"]

            if "prep_delay_start_time" not in st:
                st["prep_delay_start_time"] = 0.0
            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0

            if current_state == "ready":
                hold_prog = 0.0
                # Giai doan cho nguoi choi vao tu the chuan bi (Hinh 1: chu U vuong goc)
                rom_effective = min(1.0, prep_score / 0.70)
                rom_prog = rom_effective
                eval_data["rom_progress"] = rom_prog

                if is_prep_pose and rom_effective >= 1.0:
                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # Nguoi choi on dinh the chuan bi it nhat 0.35s de tranh nhan nham khi tay chi vo tinh luot qua
                    if (now - st["prep_hold_start_time"]) >= 0.35:
                        st["movement_state"] = "prep_delay"
                        st["prep_delay_start_time"] = now
                        st["movement_start_time"] = now
                        st["prep_hold_start_time"] = 0.0
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        feedback_code = "TRANSITION_DELAY_3"
                    else:
                        feedback_code = "PREP_POSITION"
                else:
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

            elif current_state == "prep_delay":
                # Giai doan delay 3 giay de nguoi choi tu tu truot tay len cao, tranh chan thuong
                hold_prog = 0.0
                rom_prog = 1.0
                eval_data["rom_progress"] = 1.0

                delay_elapsed = now - st["prep_delay_start_time"]
                remaining = max(0.0, 3.0 - delay_elapsed)

                if remaining > 2.0:
                    feedback_code = "TRANSITION_DELAY_3"
                elif remaining > 1.0:
                    feedback_code = "TRANSITION_DELAY_2"
                elif remaining > 0.0:
                    feedback_code = "TRANSITION_DELAY_1"

                if delay_elapsed >= 3.0:
                    st["movement_state"] = "raising"
                    feedback_code = "REACH_OVERHEAD"

            elif current_state == "raising":
                hold_prog = 0.0
                # Nguoi choi dang vuon 2 tay len cao (Hinh 2)
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog

                # Khi vuon cao dat Hinh 2:
                # BAT BUOC phai la is_hold_pose (va hold_rom >= 0.75), KHONG chap nhan the chu U
                if is_hold_pose and (hold_rom >= 0.75):
                    st["movement_state"] = "holding"
                    st["hold_start_time"] = now
                    st["last_hold_emit_time"] = now
                    st["hold_grace_start_time"] = 0.0
                    rep_id = st["current_rep_id"]
                    events.append({
                        "event": "target_reached",
                        "rep_candidate_id": rep_id,
                        "feedback_code": "TARGET_REACHED",
                    })
                    events.append({
                        "event": "hold_started",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_STARTED",
                    })
                    feedback_code = "HOLD_STARTED"
                elif is_prep_pose or (eval_data.get("angles", {}).get("avg_el_angle", 0) < 112.0):
                    # Nguoi choi van giu nguyen the chu U vuong goc: nhac nho vuon 2 tay len cao
                    feedback_code = "REACH_OVERHEAD"
                elif (eval_data.get("angles", {}).get("avg_sh_angle", 0) < 60.0) and (eval_data.get("angles", {}).get("avg_elbow_reach", 0) < -0.20):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"
                else:
                    feedback_code = "REACH_OVERHEAD"

            elif current_state == "holding":
                # TRANG THAI GIU 5 GIAY (HINH 2) - ON DINH TUYET DOI
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Dam bao ROM khong bi giat ve 0 trong qua trinh giu khi van duy tri the Hinh 2
                rom_prog = max(0.40, hold_rom) if hold_rom >= 0.40 else hold_rom
                eval_data["rom_progress"] = rom_prog

                # Yeu cau cua User: neu ROM khong xuong duoi 40% thi giu nguyen HOLDING
                if hold_rom < 0.40:
                    # Neu ha tay duoi 40%: bat dau dem an han 1.0 giay
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    if (now - st["hold_grace_start_time"]) >= 1.0:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.45,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        st["movement_state"] = "ready"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "HOLD_INTERRUPTED"
                else:
                    # Van giu tot tren 40% -> Reset grace
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"

                    # Phat hold_progress dinh ky moi 200ms
                    if (now - st["last_hold_emit_time"] >= 0.20) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": hold_duration_ms,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # Neu giu du 5 giay (100% hold)
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_duration_ms,
                            "quality": 0.98,
                            "feedback_code": "REP_VALID",
                        })
                        st["movement_state"] = "returning"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "LIFT_SUCCESS"

            elif current_state == "returning":
                hold_prog = 0.0
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog
                feedback_code = "RETURN_TO_PREP"

                # Khi nguoi choi da ha tay xuong khoi vung tren dau (reach_score < 0.40):
                if reach_score < 0.40:
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

        elif exercise_id == "horizontal_shoulder_adduction":
            # ==========================================
            # MAP 3: KHEP NGANG KHOP VAI / DANG MO NGUC 2 BEN
            # QUY TRINH 2 GIAI DOAN: CHUAN BI (HINH 1) -> DELAY 3S -> GIU 5S (HINH 2)
            # ==========================================
            prep_score = eval_data["prep_score"]
            is_prep_pose = eval_data["is_prep_pose"]
            hold_rom = eval_data["hold_rom"]
            is_hold_pose = eval_data["is_hold_pose"]
            elbow_ratio = eval_data.get("angles", {}).get("elbow_ratio", 1.0)
            wrist_ratio = eval_data.get("angles", {}).get("wrist_ratio", 1.0)

            if "prep_delay_start_time" not in st:
                st["prep_delay_start_time"] = 0.0
            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0

            if current_state == "ready":
                hold_prog = 0.0
                # Giai doan cho nguoi choi vao tu the chuan bi (Hinh 1: khep 2 khuyu tay & ban tay)
                # Tinh ROM chuan bi: prep_score tu 0.20 -> 0.55 anh xa muot ma thanh 0.0 -> 1.0
                prep_progress = max(0.0, min(1.0, (prep_score - 0.20) / (0.55 - 0.20)))

                # Khi nguoi choi dat the chuan bi (is_prep_pose):
                # ROM DAT NGAY 100% (1.0), khong bao gio bi ket duoi 100%
                if is_prep_pose:
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0

                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # On dinh the chuan bi it nhat 0.30s de chac chan nguoi choi da san sang
                    if (now - st["prep_hold_start_time"]) >= 0.30:
                        st["movement_state"] = "prep_delay"
                        st["prep_delay_start_time"] = now
                        st["movement_start_time"] = now
                        st["prep_hold_start_time"] = 0.0
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        feedback_code = "TRANSITION_DELAY_3"
                    else:
                        feedback_code = "PREP_POSITION"
                else:
                    rom_prog = prep_progress
                    eval_data["rom_progress"] = rom_prog
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

            elif current_state == "prep_delay":
                # Giai doan delay 3 giay de nguoi choi tu tu dang 2 tay sang 2 ben, tranh chan thuong
                hold_prog = 0.0
                rom_prog = 1.0
                eval_data["rom_progress"] = 1.0

                delay_elapsed = now - st["prep_delay_start_time"]
                remaining = max(0.0, 3.0 - delay_elapsed)

                if remaining > 2.0:
                    feedback_code = "TRANSITION_DELAY_3"
                elif remaining > 1.0:
                    feedback_code = "TRANSITION_DELAY_2"
                elif remaining > 0.0:
                    feedback_code = "TRANSITION_DELAY_1"

                if delay_elapsed >= 3.0:
                    st["movement_state"] = "opening"
                    feedback_code = "OPEN_ARMS"

            elif current_state == "opening":
                hold_prog = 0.0
                # Nguoi choi dang dang 2 canh tay sang 2 ben (Hinh 2)
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog

                # Khi dang rong dat Hinh 2:
                # BAT BUOC phai la is_hold_pose va hold_rom >= 0.75
                if is_hold_pose and (hold_rom >= 0.75):
                    st["movement_state"] = "holding"
                    st["hold_start_time"] = now
                    st["last_hold_emit_time"] = now
                    st["hold_grace_start_time"] = 0.0
                    rep_id = st["current_rep_id"]
                    events.append({
                        "event": "target_reached",
                        "rep_candidate_id": rep_id,
                        "feedback_code": "TARGET_REACHED",
                    })
                    events.append({
                        "event": "hold_started",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_STARTED",
                    })
                    feedback_code = "HOLD_STARTED"
                elif is_prep_pose or (elbow_ratio < 0.75):
                    # Nguoi choi van giu the khep: nhac nho dang 2 tay sang 2 ben
                    feedback_code = "OPEN_ARMS"
                elif not form_valid and (elbow_ratio < 0.50):
                    # Nguoi choi buong tay xuong duoi
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"
                else:
                    feedback_code = "OPEN_ARMS"

            elif current_state == "holding":
                # TRANG THAI GIU 5 GIAY (HINH 2) - ON DINH TUYET DOI
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Dam bao ROM khong bi giat ve 0 trong qua trinh giu khi van o Hinh 2
                if hold_rom >= 0.40:
                    rom_prog = max(0.40, hold_rom)
                else:
                    rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog

                # Yeu cua cua User: neu ROM khong xuong duoi 40% thi giu nguyen HOLDING
                if hold_rom < 0.40:
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    if (now - st["hold_grace_start_time"]) >= 1.0:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.45,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        st["movement_state"] = "ready"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "HOLD_INTERRUPTED"
                else:
                    # Van giu the Hinh 2 tot tren 40% -> Reset grace
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"

                    # Phat hold_progress dinh ky moi 200ms de Godot dieu khien song nang luong
                    if (now - st["last_hold_emit_time"] >= 0.20) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": hold_duration_ms,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # Neu giu du 5 giay (100% hold)
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_duration_ms,
                            "quality": 0.98,
                            "feedback_code": "REP_VALID",
                        })
                        st["movement_state"] = "returning"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "PUSH_SUCCESS"

            elif current_state == "returning":
                hold_prog = 0.0
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog
                feedback_code = "RETURN_TO_PREP"

                # Khi nguoi choi da khep tay lai ve truoc nguc (elbow_ratio < 0.85 hoac is_prep_pose):
                if elbow_ratio < 0.85 or is_prep_pose:
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

        elif exercise_id == "hands_behind_head":
            # ==========================================
            # MAP 4: VAN DONG KHOP VAI O TU THE 2 TAY OM DAU
            # QUY TRINH 2 GIAI DOAN: CHUAN BI (HINH 1) -> DELAY 3S -> GIU 5S (HINH 2) -> NHAY BAC
            # ==========================================
            prep_score = eval_data["prep_score"]
            is_prep_pose = eval_data["is_prep_pose"]
            hold_rom = eval_data["hold_rom"]
            is_hold_pose = eval_data["is_hold_pose"]
            elbow_ratio = eval_data.get("angles", {}).get("elbow_ratio", 1.0)
            wrist_ratio = eval_data.get("angles", {}).get("wrist_ratio", 1.0)

            if "prep_delay_start_time" not in st:
                st["prep_delay_start_time"] = 0.0
            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0
            if "last_delay_sec" not in st:
                st["last_delay_sec"] = -1

            if current_state == "ready":
                hold_prog = 0.0
                # Giai doan cho nguoi choi vao tu the chuan bi (Hinh 1: 2 tay om dau, mo rong khuyu)
                prep_progress = prep_score

                # Khi nguoi choi dat the chuan bi (is_prep_pose):
                # ROM DAT NGAY 100% (1.0), khong bao gio bi ket duoi 100%
                if is_prep_pose:
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0

                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # On dinh the chuan bi it nhat 0.25s de chac chan nguoi choi da san sang
                    if (now - st["prep_hold_start_time"]) >= 0.25:
                        st["movement_state"] = "prep_delay"
                        st["prep_delay_start_time"] = now
                        st["movement_start_time"] = now
                        st["prep_hold_start_time"] = 0.0
                        st["last_delay_sec"] = 3
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        events.append({
                            "event": "feedback",
                            "feedback_code": "TRANSITION_DELAY_3",
                        })
                        feedback_code = "TRANSITION_DELAY_3"
                    else:
                        feedback_code = "PREP_POSITION"
                else:
                    rom_prog = prep_progress
                    eval_data["rom_progress"] = rom_prog
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

            elif current_state == "prep_delay":
                # Giai doan delay 3 giay de nguoi choi tu tu khep khuyu tay, tranh chuyen dong qua nhanh gay chan thuong
                hold_prog = 0.0
                rom_prog = 1.0
                eval_data["rom_progress"] = 1.0

                delay_elapsed = now - st["prep_delay_start_time"]
                remaining = max(0.0, 3.0 - delay_elapsed)

                curr_sec = int(math.ceil(remaining))
                curr_sec = max(1, min(3, curr_sec))
                feedback_code = f"TRANSITION_DELAY_{curr_sec}"

                # Phat su kien dem lui sang Godot ngay khi chuyen giay
                if curr_sec != st.get("last_delay_sec", -1):
                    st["last_delay_sec"] = curr_sec
                    events.append({
                        "event": "feedback",
                        "feedback_code": feedback_code,
                    })

                if delay_elapsed >= 3.0:
                    st["movement_state"] = "closing"
                    st["last_delay_sec"] = -1
                    feedback_code = "CLOSE_ELBOWS"
                    events.append({
                        "event": "feedback",
                        "feedback_code": "CLOSE_ELBOWS",
                    })

            elif current_state == "closing":
                hold_prog = 0.0
                if "peak_closing_rom" not in st:
                    st["peak_closing_rom"] = 0.0

                # Chong giat lui % do rung co: theo doi moc tien do cao nhat khi khep
                if hold_rom > st["peak_closing_rom"]:
                    st["peak_closing_rom"] = hold_rom
                elif hold_rom < st["peak_closing_rom"] - 0.25:
                    # Neu nguoi choi chu dong mo tay rong ra lai thi giam dan
                    st["peak_closing_rom"] = max(hold_rom, st["peak_closing_rom"] - 0.04)

                effective_rom = max(hold_rom, st["peak_closing_rom"])

                # Nguoi choi dang khep 2 khuyu tay ve phia truoc (Hinh 2)
                # Khi da khep duoc tren 80% hoac dat is_hold_pose: ROM len tron 100%
                if is_hold_pose or effective_rom >= 0.80:
                    rom_prog = 1.0
                else:
                    rom_prog = effective_rom
                eval_data["rom_progress"] = rom_prog

                # Khi khep dat the Hinh 2:
                # Ghi nhan the Hinh 2 ngay khi is_hold_pose hoac effective_rom >= 0.75
                if is_hold_pose or (effective_rom >= 0.75 and form_valid):
                    st["movement_state"] = "holding"
                    st["peak_closing_rom"] = 0.0
                    st["hold_start_time"] = now
                    st["last_hold_emit_time"] = now
                    st["hold_grace_start_time"] = 0.0
                    rep_id = st["current_rep_id"]
                    events.append({
                        "event": "target_reached",
                        "rep_candidate_id": rep_id,
                        "feedback_code": "TARGET_REACHED",
                    })
                    events.append({
                        "event": "hold_started",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_STARTED",
                    })
                    feedback_code = "HOLD_STARTED"
                elif is_prep_pose or (elbow_ratio > 1.15):
                    # Nguoi choi van dang mo tay: nhac nho khep 2 khuyu tay ve truoc
                    st["peak_closing_rom"] = 0.0
                    feedback_code = "CLOSE_ELBOWS"
                elif not form_valid and (elbow_ratio < 0.40):
                    # Nguoi choi buong tay xuong duoi
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["peak_closing_rom"] = 0.0
                    feedback_code = "PREP_POSITION"
                    events.append({
                        "event": "feedback",
                        "feedback_code": "PREP_POSITION",
                    })
                else:
                    feedback_code = "CLOSE_ELBOWS"

            elif current_state == "holding":
                # TRANG THAI GIU 5 GIAY (HINH 2) - ON DINH TUYET DOI
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Yeu cau cua User: Khi dang trong trang thai HOLDING,
                # neu ROM khong tut xuong duoi 40% (nguoi choi khong buong tay hay doi dong tac qua nhieu)
                # thi BAT BUOC GIU NGUYEN TRANG THAI HOLDING VA KHONG DE GIAT ROM VE 0!
                if hold_rom >= 0.40:
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"

                    # Phat hold_progress dinh ky moi 150ms de Godot dieu khien thanh tien do muot ma
                    if (now - st["last_hold_emit_time"] >= 0.15) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": hold_duration_ms,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # Neu giu du 5 giay (100% hold) -> Nhan vat nhay len mot bac
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_duration_ms,
                            "quality": 0.98,
                            "feedback_code": "JUMP_SUCCESS",
                        })
                        st["movement_state"] = "returning"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "JUMP_SUCCESS"
                else:
                    # Neu ROM tut xuong duoi 40% (nguoi choi mo toang tay ra lai hoac buong thong tay)
                    rom_prog = hold_rom
                    eval_data["rom_progress"] = rom_prog
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    # Chi huy trang thai holding sau 1.2 giay nguoi choi thuc su bo the
                    if (now - st["hold_grace_start_time"]) >= 1.2:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.45,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        st["movement_state"] = "ready"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "HOLD_INTERRUPTED"

            elif current_state == "returning":
                hold_prog = 0.0
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog
                feedback_code = "RETURN_TO_PREP"

                # Khi nguoi choi da mo 2 khuyu tay ra lai 2 ben (elbow_ratio >= 1.15 hoac is_prep_pose):
                if elbow_ratio >= 1.15 or is_prep_pose:
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["peak_closing_rom"] = 0.0
                    feedback_code = "PREP_POSITION"
                    events.append({
                        "event": "feedback",
                        "feedback_code": "PREP_POSITION",
                    })

        else:
            # ==========================================
            # DONG TAC CO GIU TINH (MAP 5: KEO CANG CANH TAY QUA NGUC - 30S)
            # ==========================================
            if current_state == "ready":
                if rom_prog >= 0.25 and form_valid:
                    st["movement_state"] = "contracting"
                    st["movement_start_time"] = now
                    st["hold_grace_start_time"] = 0.0
                    rep_id = self._next_rep_candidate_id(exercise_id)
                    events.append({
                        "event": "movement_started",
                        "rep_candidate_id": rep_id,
                        "feedback_code": "MOVEMENT_STARTED",
                    })

            elif current_state == "contracting":
                feedback_code = "CONTINUE_MOVEMENT"
                # Khi nguoi choi keo cang dat nguong (>= 0.70 hoac da duoc boost 1.0):
                # Lap tuc khoa ROM = 100%, chuyen sang HOLD 30s va nhan vat thien!
                if (rom_prog >= st["target_rom_ratio"] or rom_prog >= 0.70) and form_valid:
                    st["movement_state"] = "holding"
                    st["hold_start_time"] = now
                    st["last_hold_emit_time"] = now
                    st["hold_grace_start_time"] = 0.0
                    st["peak_rom_achieved"] = 1.0
                    rep_id = st["current_rep_id"]
                    events.append({
                        "event": "target_reached",
                        "rep_candidate_id": rep_id,
                        "feedback_code": "TARGET_REACHED",
                    })
                    events.append({
                        "event": "hold_started",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_STARTED",
                    })
                elif rom_prog < 0.15:
                    st["movement_state"] = "ready"
                    st["hold_grace_start_time"] = 0.0
                    st["active_stretch_side"] = "none"

            elif current_state == "holding":
                feedback_code = "KEEP_POSITION"
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # KHOA SAN ROM LUON LA 100% TRONG SUOT QUA TRINH HOLDING!
                # Ngan chan triet de hien tuong ROM bi giat ve 0% hoac nhay lung tung khi dang giu 30s
                rom_prog = 1.0
                eval_data["rom_progress"] = 1.0

                # Phat hold_progress dinh ky moi 150ms LIEN TUC giup UI Godot chay muot ma khong bi dung khung
                if (now - st["last_hold_emit_time"] >= 0.15) and hold_prog < 1.0:
                    st["last_hold_emit_time"] = now
                    events.append({
                        "event": "hold_progress",
                        "rep_candidate_id": st["current_rep_id"],
                        "hold_elapsed_ms": hold_elapsed_ms,
                        "hold_target_ms": hold_duration_ms,
                        "hold_progress": round(hold_prog, 2),
                        "feedback_code": "KEEP_POSITION",
                    })

                # Nguoi choi chi bi xem la loi tu the khi THUC SU buong tay xuong hong hoac tha long hoan toan
                # An han an toan 2.5s tranh viec rung tay nhe hoac MediaPipe chap chon
                is_posture_fault = not form_valid

                if is_posture_fault:
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    # Chi phat hold_interrupted khi buong tay qua thoi gian an han 2.5 giay
                    if (now - st["hold_grace_start_time"]) >= 2.5:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.45,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        feedback_code = "HOLD_INTERRUPTED"
                        st["movement_state"] = "ready"
                        st["peak_rom_achieved"] = 0.0
                        st["peak_stretch_rom"] = 0.0
                        st["hold_grace_start_time"] = 0.0
                        st["active_stretch_side"] = "none"
                else:
                    # Form tot -> reset bo dem an han
                    st["hold_grace_start_time"] = 0.0

                # Neu giu du 30 giay quy dinh
                if hold_prog >= 1.0:
                    rep_id = st["current_rep_id"]
                    total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                    events.append({
                        "event": "hold_completed",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_COMPLETED",
                    })
                    events.append({
                        "event": "rep_completed",
                        "rep_candidate_id": rep_id,
                        "duration_ms": total_duration_ms,
                        "max_rom_ratio": 1.0,
                        "hold_duration_ms": hold_duration_ms,
                        "quality": 1.0,
                        "feedback_code": "REP_VALID",
                    })
                    feedback_code = "REP_VALID"
                    st["movement_state"] = "returning"
                    st["hold_grace_start_time"] = 0.0
                    st["peak_stretch_rom"] = 0.0
                    st["active_stretch_side"] = "none"

            elif current_state == "returning":
                feedback_code = "POSITION_OK"
                # Cho nguoi choi tha long tay ve de nghi 30s hoac chuyen tay tiep theo
                if eval_data["rom_progress"] < 0.40:
                    st["movement_state"] = "ready"
                    st["peak_rom_achieved"] = 0.0
                    st["hold_grace_start_time"] = 0.0
                    st["active_stretch_side"] = "none"

        st["last_rom_progress"] = rom_prog
        st["last_hold_progress"] = hold_prog

        # 3. Dong goi pose_frame metrics
        movement_duration_ms = 0
        if st["movement_start_time"] > 0:
            movement_duration_ms = int((now - st["movement_start_time"]) * 1000)

        pose_metrics = {
            "angles": eval_data["angles"],
            "exercise": {
                "exercise_id": exercise_id,
                "movement_state": st["movement_state"],
                "form_valid": form_valid,
                "rom_progress": round(rom_prog, 2),
                "hold_progress": round(hold_prog, 2),
                "movement_duration_ms": movement_duration_ms,
                "quality": 0.92 if form_valid else 0.50,
                "feedback_code": feedback_code,
            },
        }

        return pose_metrics, events