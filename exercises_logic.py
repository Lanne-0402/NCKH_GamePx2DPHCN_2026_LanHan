import math

class ExercisesEvaluator:
    def __init__(self):
        self.state = {
            "scapular_retraction":{"state":"idle", "rep_count":0, "current_rep_id":None},
            "wall_abduction_external_rotation": {"state":"idle", "rep_count":0, "current_rep_id":None},
            "horizontal_shoulder_adduction": {"state":"idle", "rep_count":0, "current_rep_id":None},
            "hands_behind_head": {"state":"idle", "rep_count":0, "current_rep_id":None},
            "cross_body_shoulder_stretch": {"state":"idle", "rep_count":0, "current_rep_id":None},
        }

    def calculate_angle(self, p1, p2, p3):
        radians = math.atan2(p3.y -  p2.y, p3.x - p2.x) - math.atan2(p1.y - p2.y, p1.x - p2.x)
        angle = abs(math.degrees(radians))
        if angle > 180.0:
            angle = 360.0 - angle
        return angle
    
    #Tinh khoang cach 2D giua 2 diem
    def calculate_2d_distance(self, p1, p2):
        return math.sqrt((p1.x - p2.x)**2 + (p1.y - p2.y)**2)

    # Can xac dinh thong so do co ngan khuyu tay va co tay
    def evaluate_map1_scapular_retraction(self, landmarks):
        l_shoulder, r_shoulder = landmarks[11], landmarks[12]
        l_elbow, r_elbow = landmarks[13], landmarks[14]
        l_wrist, r_wrist = landmarks[15], landmarks[16]
        # So sanh do sau Z cua khop vai > khuyu tay
        l_depth_diff = l_elbow.z - l_shoulder.z
        r_depth_diff = r_elbow.z - r_shoulder.z
        # Tinh khoang cach 2D (do co ngan) giua khuyu tay va co tay
        l_2d_dist = self.calculate_2d_distance(l_elbow, l_wrist)
        r_2d_dist = self.calculate_2d_distance(r_elbow, r_wrist)

        return {
            "left_z_diff": l_depth_diff,
            "right_z_diff": r_depth_diff,
            "left_2d_dist": l_2d_dist,
            "right_2d_dist": r_2d_dist
        }

    def evaluate_map2_wall_abduction(self, landmarks):
        l_hip, r_hip = landmarks[23], landmarks[24]
        l_shoulder, r_shoulder = landmarks[11], landmarks[12]
        l_elbow, r_elbow = landmarks[13], landmarks[14]
        l_wrist, r_wrist = landmarks[15], landmarks[16]

        l_shoulder_angle = self.calculate_2d_distance(l_hip, l_shoulder, l_elbow)
        r_shoulder_angle = self.calculate_2d_distance(r_hip, r_shoulder, r_elbow)

        l_form_valid = l_wrist.y < l_elbow.y
        r_form_valid = r_wrist.y < r_elbow.y

        return {
            "left_angle": l_shoulder_angle,
            "right_angle": r_shoulder_angle,
            "form_valid": l_form_valid and r_form_valid
        }

    def evaluate_map3_horizontal_shoulder_adduction(self, landmarks):
        l_shoulder, r_shoulder = landmarks[11], landmarks[12]
        l_elbow, r_elbow = landmarks[13], landmarks[14]
        l_wrist, r_wrist = landmarks[15], landmarks[16]
        #Khuyu tay ngang = vai, sai so 0.1
        y_aligned_left = abs(l_elbow.y - l_shoulder.y) < 0.1
        y_aligned_right = abs(r_elbow.y - r_shoulder.y) < 0.1
        #Co tay sat nhau, sai so 0.15
        wrists_together = abs(l_wrist.x - r_wrist.x) < 0.15
        #Khuyu tay huong ve truoc, Z am hon vai, khoang cach do sau la 0.1
        elbows_forward_left = l_elbow.z < (l_shoulder.z - 0.1)
        elbows_forward_right = r_elbow.z < (r_shoulder.z - 0.1)

        is_ready = y_aligned_left and y_aligned_right and wrists_together and elbows_forward_left and elbows_forward_right
        return is_ready

    def evaluate_map4_hands_behind_head(self, landmarks):
        l_elbow, r_elbow = landmarks[13], landmarks[14]
        l_wrist, r_wrist = landmarks[15], landmarks[16]
        l_ear, r_ear = landmarks[7], landmarks[8]
        #Giam khoang cach 2 khuyu tay khi player gap 2tay ve truoc
        elbows_distance = abs(l_elbow.x - r_elbow.x)
        #Dam bao player giu 2 tay gap o muc on dinh (can bi che khuat, can xem lai)
        l_hand_at_head = self.calculate_2d_distance(l_wrist, l_ear) < 0.2
        r_hand_at_head = self.calculate_2d_distance(r_wrist, r_ear) < 0.2

        return {
            "elbow_distance": elbows_distance,
            "form_valid": l_hand_at_head and r_hand_at_head
        }

    def evaluate_map5_cross_body_stretch(self, landmarks):
        l_shoulder, r_shoulder = landmarks[11], landmarks[12]
        l_elbow, r_elbow = landmarks[13], landmarks[14]
        l_wrist, r_wrist = landmarks[15], landmarks[16]
        #keo tay qua nguc, khoang cach giua co tay nay va vai kia se giam
        l_wrist_to_r_shoulder = self.calculate_2d_distance(l_wrist, r_shoulder)
        r_wrist_to_l_shoulder = self.calculate_2d_distance(r_wrist, l_shoulder)

        l_elbow_angle = self.calculate_angle(l_shoulder, l_elbow, l_wrist)
        r_elbow_angle = self.calculate_angle(r_shoulder, r_elbow, r_wrist)

        return {
            "left_stretch_dist": l_wrist_to_r_shoulder,
            "right_stretch_dist": r_wrist_to_l_shoulder,
            "left_elbow_straight": l_elbow_angle > 150,
            "right_elbow_straight": r_elbow_angle > 150
        }

    def generate_rep_id(self, exercise_id):
        self.state[exercise_id]["rep_count"] += 1
        count = self.state[exercise_id]["rep_count"]
        new_id = f"rep-{exercise_id}-{count:03d}"
        self.state[exercise_id]["current_rep_id"] = new_id
        return new_id