import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Pose
import tf_transformations
import pyspacemouse
import math

class SpaceMouseHandler(Node):
    def __init__(self):
        super().__init__('spacemouse_handler')
        self.publisher_ = self.create_publisher(Pose, 'platform_pose', 10)
        self.timer = self.create_timer(0.01, self.publish_pose)

        """Initialize and open the SpaceMouse."""
        self._is_open = pyspacemouse.open()

        if not self._is_open:
            raise ConnectionError("Failed to connect to the SpaceMouse.")

    def publish_pose(self):
        """
        Read the state of the SpaceMouse and publish this state to the 'platform_pose' topic
        """

        # Set the multipliers for each axis (mm, deg)
        xy_mult = 150.0  # mm
        z_mult = 150.0   # mm
        pitch_roll_mult = 30.0  # deg
        yaw_mult = 25.0  # deg

        # Initialise pose object
        pose = Pose() 

        # Read the state of the spacemouse
        state = pyspacemouse.read()

        # Apply multipliers and convert to radians
        # NOTE Not sure why I need to swap pitch and roll. This wasn't the case pre-ROS...
        # (though I previously *did* need negatives out the front of pitch and yaw)
        roll = math.radians(-state.pitch * pitch_roll_mult)
        pitch = math.radians(state.roll * pitch_roll_mult)
        yaw = math.radians(-state.yaw * yaw_mult)

        # Convert orientation from Euler angles to quaternions
        quaternion_ori = tf_transformations.quaternion_from_euler(roll, pitch, yaw, axes='sxyz')
        
        # Construct the pose message
        pose.position.x = state.x * xy_mult
        pose.position.y = state.y * xy_mult
        pose.position.z = state.z * z_mult
        pose.orientation.x = quaternion_ori[0]
        pose.orientation.y = quaternion_ori[1]
        pose.orientation.z = quaternion_ori[2]
        pose.orientation.w = quaternion_ori[3]

        # If wanting to print readings
        # self.get_logger().info(f'x: {state.x:.2f}, y: {state.y:.2f}, z: {state.z:.2f}, roll: {roll:.2f}, pitch: {pitch:.2f}, yaw: {yaw:.2f}')
        # self.get_logger().info(f'qx: {pose.orientation.x:.2f}, qy: {pose.orientation.y:.2f}, qz: {pose.orientation.z:.2f}, qw: {pose.orientation.w:.2f}')

        self.publisher_.publish(pose)

        

def main(args=None):
    rclpy.init(args=args)
    node = SpaceMouseHandler()
    rclpy.spin(node)
    rclpy.shutdown()

        
if __name__ == "__main__":
    main()