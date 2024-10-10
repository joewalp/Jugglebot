import time
import rclpy
from rclpy.node import Node
from rclpy.action import ActionServer, CancelResponse, GoalResponse
from jugglebot_interfaces.msg import (
    CanTrafficReportMessage,
    LegsTargetReachedMessage,
    SetMotorVelCurrLimitsMessage,
    SetTrapTrajLimitsMessage,
    HandTelemetryMessage,
    HeartbeatMsg,
)
from jugglebot_interfaces.srv import ODriveCommandService, GetTiltReadingService
from jugglebot_interfaces.action import HomeMotors
from std_msgs.msg import Float64MultiArray
from std_srvs.srv import Trigger
from .can_interface import CANInterface


class CanInterfaceNode(Node):
    def __init__(self):
        super().__init__('can_interface_node')

        # Publisher for HeartbeatMsg
        self.heartbeat_publisher = self.create_publisher(HeartbeatMsg, 'heartbeat_topic', 10)

        # Initialize the CANInterface
        self.can_handler = CANInterface(logger=self.get_logger(), heartbeat_publisher=self.heartbeat_publisher)

        # Initialize services
        self.encoder_search_service = self.create_service(Trigger, 'encoder_search', self.run_encoder_search)
        self.end_session_service = self.create_service(Trigger, 'end_session', self.end_session)
        self.odrive_command_service = self.create_service(
            ODriveCommandService, 'odrive_command', self.odrive_command_callback
        )
        self.report_tilt_service = self.create_service(GetTiltReadingService, 'get_platform_tilt', self.report_tilt)

        # Initialize actions
        self.home_robot_action = ActionServer(self, HomeMotors, 'home_motors', self.home_robot)

        # Initialize subscribers
        self.motor_pos_subscription = self.create_subscription(
            Float64MultiArray, 'leg_lengths_topic', self.handle_movement, 10
        )
        self.motor_vel_curr_limits_subscription = self.create_subscription(
            SetMotorVelCurrLimitsMessage, 'set_motor_vel_curr_limits', self.motor_vel_curr_limits_callback, 10
        )
        self.motor_trap_traj_limits_subscription = self.create_subscription(
            SetTrapTrajLimitsMessage, 'leg_trap_traj_limits', self.motor_trap_traj_limits_callback, 10
        )

        # Initialize publishers for hardware data
        self.position_publisher = self.create_publisher(Float64MultiArray, 'leg_positions', 10)
        self.velocity_publisher = self.create_publisher(Float64MultiArray, 'leg_velocities', 10)
        self.iq_publisher = self.create_publisher(Float64MultiArray, 'leg_iqs', 10)
        self.can_traffic_publisher = self.create_publisher(CanTrafficReportMessage, 'can_traffic', 10)
        self.hand_telemetry_publisher = self.create_publisher(HandTelemetryMessage, 'hand_telemetry', 10)
        self.platform_target_reached_publisher = self.create_publisher(LegsTargetReachedMessage, 'platform_target_reached', 10)

        # Initialize target positions and status flags
        self.legs_target_position = [None] * 6
        self.legs_target_reached = [False] * 6
        self.is_fatal = False
        self.shutdown_flag = False

        # Initialize timers
        self.platform_target_reached_timer = self.create_timer(
            0.1, self.check_platform_target_reached_status
        )
        self.timer_canbus = self.create_timer(timer_period_sec=0.001, callback=self._poll_can_bus)

        self.num_axes = 7

        # Initialize variables to store the last received data
        self.last_motor_positions = [None] * self.num_axes
        self.last_motor_velocities = [None] * self.num_axes
        self.last_motor_iqs = [None] * self.num_axes

        # Register callbacks with CANInterface
        self.can_handler.register_callback('leg_positions', self.publish_motor_positions)
        self.can_handler.register_callback('leg_velocities', self.publish_motor_velocities)
        self.can_handler.register_callback('leg_iqs', self.publish_motor_iqs)
        self.can_handler.register_callback('can_traffic', self.publish_can_traffic)
        self.can_handler.register_callback('hand_telemetry', self.publish_hand_telemetry)

    #########################################################################################################
    #                                     Interfacing with the CAN bus                                      #
    #########################################################################################################

    def _poll_can_bus(self):
        # Polls the CAN bus to check for new updates
        self.can_handler.fetch_messages()
        if self.can_handler.fatal_issue or self.can_handler.fatal_can_issue:
            self._on_fatal_issue()

    def _on_fatal_issue(self):
        if not self.is_fatal:
            self.get_logger().fatal(
                "Fatal issue detected. Robot will be unresponsive until errors are cleared",
                throttle_duration_sec=3.0,
            )
            self.is_fatal = True

    def motor_vel_curr_limits_callback(self, msg):
        """Set the absolute velocity and current limits for all motors."""
        try:
            # Extract the limits from the message
            leg_vel_limit = msg.legs_vel_limit
            leg_curr_limit = msg.legs_curr_limit
            hand_vel_limit = msg.hand_vel_limit
            hand_curr_limit = msg.hand_curr_limit

            self.can_handler.set_absolute_vel_curr_limits(
                leg_vel_limit=leg_vel_limit,
                leg_current_limit=leg_curr_limit,
                hand_vel_limit=hand_vel_limit,
                hand_current_limit=hand_curr_limit,
            )

            self.get_logger().info(
                f"Motor velocity and current limits updated: "
                f"Leg Vel={leg_vel_limit}, Leg Curr={leg_curr_limit}, "
                f"Hand Vel={hand_vel_limit}, Hand Curr={hand_curr_limit}"
            )
        except Exception as e:
            self.get_logger().error(f"Error setting motor velocity and current limits: {e}")

    def motor_trap_traj_limits_callback(self, msg):
        """Set the trapezoidal trajectory limits for all leg motors."""
        try:
            # Extract the limits from the message
            leg_vel_limit = msg.trap_vel_limit
            leg_acc_limit = msg.trap_acc_limit
            leg_dec_limit = msg.trap_dec_limit

            self.can_handler.set_trap_traj_vel_acc_limits(
                velocity_limit=leg_vel_limit,
                acceleration_limit=leg_acc_limit,
                deceleration_limit=leg_dec_limit,
            )

            self.get_logger().info(
                f"Updated trapezoidal trajectory limits: "
                f"Vel={leg_vel_limit}, Acc={leg_acc_limit}, Dec={leg_dec_limit}"
            )
        except Exception as e:
            self.get_logger().error(f"Error setting trapezoidal trajectory limits: {e}")

    #########################################################################################################
    #                                        Commanding Jugglebot                                           #
    #########################################################################################################

    def run_encoder_search(self, request, response):
        """Service callback to run the encoder search."""

        self.get_logger().info("Encoder search initiated.")

        try:
            self.can_handler.run_encoder_search()
            response.success = True
            response.message = 'Encoder search complete!'
        except Exception as e:
            self.get_logger().error(f"Error running encoder search: {e}")
            response.success = False
            response.message = f"Error running encoder search: {e}"

        return response

    def home_robot(self, goal_handle):
        """Action server callback to home the robot."""
        try:
            # Check if the robot is in a fatal state
            if self.is_fatal or self.can_handler.fatal_issue or self.can_handler.fatal_can_issue:
                self._on_fatal_issue()
                goal_handle.abort()
                return

            # Start the robot homing
            success = self.can_handler.home_robot()

            self.get_logger().info("Robot homing complete.")

            # Publish the result
            goal_handle.succeed()
            result = HomeMotors.Result()
            result.success = success
            return result
            
        except Exception as e:
            self.get_logger().error(f"Error homing robot: {e}")
            goal_handle.abort()

    def handle_movement(self, msg):
        """Handle movement commands for the robot."""
        try:
            if self.is_fatal or self.can_handler.fatal_issue or self.can_handler.fatal_can_issue:
                self._on_fatal_issue()
                return

            # Extract the leg lengths
            motor_positions = msg.data

            # Store these positions as the target positions
            self.legs_target_position = motor_positions

            for axis_id, setpoint in enumerate(motor_positions):
                self.can_handler.send_position_target(axis_id=axis_id, setpoint=setpoint)
                # self.get_logger().debug(f'Motor {axis_id} commanded to setpoint {setpoint}')

        except Exception as e:
            self.get_logger().error(f"Error in handle_movement: {e}")

    def shutdown_robot(self):
        """Shutdown procedure for the robot."""
        try:
            # Send the robot home and put all motors in IDLE
            self.get_logger().info("Initiating robot shutdown sequence...")

            # Start by lowering the max speed
            self.can_handler.set_absolute_vel_curr_limits(leg_vel_limit=2.5)
            time.sleep(1.0)

            # Command all motors to move home
            for axis_id in range(6):
                self.can_handler.send_position_target(axis_id=axis_id, setpoint=0.0)
                time.sleep(0.001)

            # Wait until all motors have reached home
            time.sleep(0.5)
            self.can_handler.fetch_messages()

            while not all(self.can_handler.trajectory_done[:6]):
                self.can_handler.fetch_messages()
                time.sleep(0.01)

            time.sleep(1.0)

            # Put motors into IDLE
            self.can_handler.set_leg_odrive_state(requested_state='IDLE')
            self.can_handler.set_requested_state(axis_id=6, requested_state='IDLE')

            self.get_logger().info("Robot shutdown sequence completed.")
        except Exception as e:
            self.get_logger().error(f"Error during robot shutdown: {e}")

    def odrive_command_callback(self, request, response):
        """Service callback for ODrive commands."""
        command = request.command

        try:
            if command == 'clear_errors':
                self.can_handler.clear_errors()
                response.success = True
                response.message = 'ODrive errors cleared.'
                self.is_fatal = False  # Reset the fatal flag now that errors have been cleared
                self.get_logger().info("ODrive errors cleared.")

            elif command == 'reboot_odrives':
                self.can_handler.reboot_odrives()
                response.success = True
                response.message = 'ODrives rebooted.'
                self.get_logger().info("ODrives rebooted.")

            else:
                response.success = False
                response.message = f'Invalid command: {command}'
                self.get_logger().warning(f"Received invalid ODrive command: {command}")

        except Exception as e:
            self.get_logger().error(f"Error in odrive_command_callback: {e}")
            response.success = False
            response.message = f"Error executing command {command}: {e}"

        return response

    def check_platform_target_reached_status(self):
        """Check whether the robot has reached its target and publish the result."""
        try:
            # Check if there are any target positions set
            if (
                None in self.legs_target_position
                or None in self.last_motor_positions
                or None in self.last_motor_velocities
            ):
                return

            # Set thresholds
            position_threshold = 0.01  # Revs (approx 0.7 mm with the 22 mm string spool)
            velocity_threshold = 0.1  # Revs/s

            # Check whether each leg has reached its target and is stationary
            for i, (setpoint, meas_pos, meas_vel) in enumerate(
                zip(
                    self.legs_target_position,
                    self.last_motor_positions,
                    self.last_motor_velocities,
                )
            ):
                if (
                    abs(meas_pos - setpoint) < position_threshold
                    and abs(meas_vel) < velocity_threshold
                ):
                    self.legs_target_reached[i] = True
                else:
                    self.legs_target_reached[i] = False

            # Publish the result
            msg = LegsTargetReachedMessage()
            msg.leg0_has_arrived = self.legs_target_reached[0]
            msg.leg1_has_arrived = self.legs_target_reached[1]
            msg.leg2_has_arrived = self.legs_target_reached[2]
            msg.leg3_has_arrived = self.legs_target_reached[3]
            msg.leg4_has_arrived = self.legs_target_reached[4]
            msg.leg5_has_arrived = self.legs_target_reached[5]

            self.platform_target_reached_publisher.publish(msg)
        except Exception as e:
            self.get_logger().error(f"Error checking platform target reached status: {e}")

    #########################################################################################################
    #                                   Interfacing with the ROS Network                                    #
    #########################################################################################################

    def report_tilt(self, request, response):
        """Service callback to report the platform tilt."""
        try:
            tilt_x, tilt_y = self.can_handler.get_tilt_sensor_reading()
            response.tilt_readings = [tilt_x, tilt_y]
            self.get_logger().info(f"Reported tilt readings: X={tilt_x}, Y={tilt_y}")
        except Exception as e:
            self.get_logger().error(f"Error reporting tilt: {e}")
            response.tilt_readings = [None, None]

        return response

    def publish_motor_positions(self, position_data):
        """Publish motor positions."""
        try:
            motor_positions = Float64MultiArray()
            motor_positions.data = position_data

            # Store the last received positions
            self.last_motor_positions = position_data

            self.position_publisher.publish(motor_positions)
        except Exception as e:
            self.get_logger().error(f"Error publishing motor positions: {e}")

    def publish_motor_velocities(self, velocity_data):
        """Publish motor velocities."""
        try:
            motor_velocities = Float64MultiArray()
            motor_velocities.data = velocity_data

            # Store the last received velocities
            self.last_motor_velocities = velocity_data

            self.velocity_publisher.publish(motor_velocities)
        except Exception as e:
            self.get_logger().error(f"Error publishing motor velocities: {e}")

    def publish_motor_iqs(self, iq_data):
        """Publish motor IQs."""
        try:
            motor_iqs = Float64MultiArray()
            motor_iqs.data = iq_data

            # Store the last received IQs
            self.last_motor_iqs = iq_data

            self.iq_publisher.publish(motor_iqs)
        except Exception as e:
            self.get_logger().error(f"Error publishing motor IQs: {e}")

    def publish_can_traffic(self, can_traffic_data):
        """Publish CAN traffic reports."""
        try:
            msg = CanTrafficReportMessage()
            msg.received_count = can_traffic_data['received_count']
            msg.report_interval = can_traffic_data['report_interval']

            self.can_traffic_publisher.publish(msg)
        except Exception as e:
            self.get_logger().error(f"Error publishing CAN traffic: {e}")

    def publish_hand_telemetry(self, hand_telemetry_data):
        """Publish hand telemetry data."""
        try:
            msg = HandTelemetryMessage()
            msg.timestamp = self.get_clock().now().to_msg()
            msg.position = hand_telemetry_data['position']
            msg.velocity = hand_telemetry_data['velocity']

            self.hand_telemetry_publisher.publish(msg)
        except Exception as e:
            self.get_logger().error(f"Error publishing hand telemetry: {e}")

    #########################################################################################################
    #                                          Managing the Node                                            #
    #########################################################################################################

    def on_shutdown(self):
        """Handle node shutdown."""
        self.get_logger().info("Shutting down CanInterfaceNode...")
        try:
            self.shutdown_robot()
            self.can_handler.shutdown()
        except Exception as e:
            self.get_logger().error(f"Error during node shutdown: {e}")

    def end_session(self, request, response):
        """Service callback to end the session."""
        self.get_logger().info("End session requested. Shutting down...")
        response.success = True
        response.message = "Session ended. Shutting down node."
        self.shutdown_flag = True
        return response


def main(args=None):
    rclpy.init(args=args)
    node = CanInterfaceNode()

    try:
        while rclpy.ok() and not node.shutdown_flag:
            rclpy.spin_once(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.on_shutdown()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()