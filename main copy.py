import asyncio
import cv2
import mediapipe as mp
import websockets
import json
import time
from exercises_logic import ExercisesEvaluator


evaluator = ExercisesEvaluator()

app_state = {
    "session_id": None,
    "current_exercise": None,
    "is_exercising": False,
    "connected_client": None
}

latest_result = None
def update_result(result, output_image, timestamp_ms):
    global latest_result
    latest_result = result

BaseOptions = mp.tasks.BaseOptions
PoseLandmarker = mp.tasks.vision.PoseLandmarker
PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
VisionRunningMode = mp.tasks.vision.RunningMode

model_path = "pose_landmarker_full.task"
options = PoseLandmarkerOptions(base_options=BaseOptions(model_asset_path=model_path), running_mode=VisionRunningMode.LIVE_STREAM, result_callback=update_result)
landmarker = PoseLandmarker.create_from_options(options)

async def websocket_handler(websocket):
    print("Godot dang co gang ket noi...")
    app_state["connected_client"] = websocket

    server_hello = {
        "contract_version": "1.0.0",
        "type": "server_hello",
        "message_id": f"msg-{int(time.time()*1000)}",
        "session_id": None,
        "timestamp_ms": int(time.time()*1000),
        "source": "backend",
        "payload": {
            "backend_version": "0.1.0",
            "pose_engine": "mediapipe",
            "camera_available": True,
            "supported_exercise": [
                "scapular_retraction",
                "wall_abduction_external_rotation",
                "horizontal_shoulder_adduction",
                "hands_behind_head",
                "cross_body_shoulder_stretch"
            ],
            "suppported features": ["pose_tracking", "joint_angles"]
        } 
    }
    await websocket.send(json.dumps(server_hello))
    print("Gui server_hello cho Godot")

    try:
        async for message in websocket:
            data = json.loads(message)
            msg_type = data.get("type")
            if msg_type == "client_hello":
                print(f"Da ket noi voi Frontend, {data['payload']['application']}")

            elif msg_type == "start_exercise":
                app_state["session_id"] = data.get("session_id")
                app_state["current_exercise"] = data["payload"]["exercise_id"]
                app_state["is_exercising"] = True
                print(f"Godot yeu cau bat dau bai tap: {app_state['current_exercise']}")

            elif msg_type == "stop_exercise":
                app_state["is_exercising"] = False
                print(f"Godot yeu cau dung bai tap.")
    except websockets.exceptions.ConnectionClosed:
        print("Godot da ngat ket noi.")
    finally:
        app_state["connected_client"] = None
        app_state["is_exercising"] = False

async def process_camera():
    cap = cv2.VideoCapture(0)
    target_fps = 30
    frame_interval = 1.0 / target_fps
    last_send_time = 0
    frame_count = 0

    while cap.isOpened():
        sucess, frame = cap.read()
        if not sucess:
            await asyncio.sleep(0.1)
            continue
        frame = cv2.flip(frame, 1)
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        timestamp_ms = int(time.time()*1000)

        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
        landmarker.detect_async(mp_image, timestamp_ms)
        current_time = time.time()

        if app_state["connected_client"] and app_state["is_exercising"] and latest_result and latest_result.pose_landmarks:
            if current_time - last_send_time >= frame_interval:
                landmarks = latest_result.pose_landmarks[0]
                exercise_id = app_state["current_exercise"]

                metrics = {}
                if exercise_id == "scapular_retraction":
                    metrics = evaluator.evaluate_map1_scapular_retraction(landmarks)
                elif exercise_id == "wall_abduction_external_rotation":
                    metrics = evaluator.evaluate_map2_wall_abduction(landmarks)
                elif exercise_id == "horizontal_shoulder_adduction":
                    metrics = evaluator.evaluate_map3_horizontal_shoulder_adduction(landmarks)
                elif exercise_id == "hands_behind_head":
                    metrics = evaluator.evaluate_map4_hands_behind_head(landmarks)
                elif exercise_id == "cross_body_shoulder_stretch":
                    metrics = evaluator.evaluate_map5_cross_body_stretch(landmarks)
                frame_count += 1
                pose_frame = {
                    "contract_version": "1.0.0",
                    "type": "pose_frame",
                    "message_id": f"msg-pose-{frame_count}",
                    "session_id": app_state["session_id"],
                    "timestamp_ms": timestamp_ms,
                    "source": "backend",
                    "payload": {
                        "frame_id": frame_count,
                        "tracking": {
                            "person_detected": True,
                            "confidence": 0.95,
                            "required_body_visible": True
                        },
                        "angles": metrics,
                        "exercise": {
                            "exercise_id": exercise_id,
                            "movement_state": "contracting",
                            "form_valid": metrics.get("form_valid", True),
                            "rom_progress": 0.0,
                            "hole_progress": 0.0,
                            "movement_duration_ms": 0,
                            "quantity": 0.9,
                            "feedback_code": "POSITION_OK"
                        }
                    }
                }
                await app_state["connected_client"].send(json.dumps(pose_frame))
                last_send_time = current_time

        cv2.imshow("Camera, nhan 'Esc' de thoat", frame)
        if cv2.waitKey(5) & 0xFF == 27: 
            break
        await asyncio.sleep(0.001)

    cap.release()
    cv2.destroyAllWindows()

async def main():
    print("Khoi dong may chu WebSocket...")
    server = await websockets.serve(websocket_handler, "127.0.0.1", 8765)
    print("WebSocket Server dang chay tai ws://127.0.0.1:8765")
    await process_camera()
    server.close()
    await server.wait_closed()
if __name__ == "__main__":
    asyncio.run(main())