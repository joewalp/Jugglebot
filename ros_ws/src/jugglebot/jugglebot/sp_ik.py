import rclpy
from rclpy.node import Node
import numpy as np
from geometry_msgs.msg import Pose
from std_msgs.msg import Float64MultiArray
from jugglebot_interfaces.srv import GetRobotGeometry
import tf_transformations

class SPInverseKinematics(Node):
    def __init__(self):
        super().__init__('sp_ik')

        # Set up service client to get robot geometry
        self.geometry_client = self.create_client(GetRobotGeometry, 'get_robot_geometry')
        
        while not self.geometry_client.wait_for_service(timeout_sec=1.0):
                self.get_logger().info('Waiting for "get_robot_geometry" service...')

        self.send_geometry_request()

        self.subscription = self.create_subscription(Pose, 'platform_pose', self.pose_callback, 10)
        self.subscription  # Prevent "unused variable" warning

        self.publisher = self.create_publisher(Float64MultiArray, 'leg_lengths', 10)

        # Initialize flag to track whether geometry data has been received or not
        self.has_geometry_data = False

        # Initialize geometry terms to be populated with a call to the get_robot_geometry service
        self.start_pos = None         # Base frame
        self.base_nodes = None        # Base frame
        self.init_plat_nodes = None   # Platform frame
        self.init_arm_nodes = None    # Platform frame
        self.init_hand_nodes = None   # Platform frame

        self.init_leg_lengths = None
        self.leg_stroke = None
        self.hand_stroke = None # For checking if the hand string is overextended

        self.new_plat_nodes = None    # Base frame
        self.new_arm_nodes = None     # Base frame
        self.new_hand_nodes = None    # Base frame

    def send_geometry_request(self):
        req = GetRobotGeometry.Request()
        self.future = self.geometry_client.call_async(req)
        self.future.add_done_callback(self.handle_geometry_response)

    def handle_geometry_response(self, future):
        response = future.result()
        if response is not None:
            # Store the geometry data after converting it to numpy arrays
            self.start_pos = np.array(response.start_pos).reshape(3, 1)
            self.base_nodes = np.array(response.base_nodes).reshape(7, 3)
            self.init_plat_nodes = np.array(response.init_plat_nodes).reshape(7, 3)
            self.init_arm_nodes = np.array(response.init_arm_nodes).reshape(6, 3)
            self.init_hand_nodes = np.array(response.init_hand_nodes).reshape(3, 3)
            self.init_leg_lengths = np.array(response.init_leg_lengths).reshape(7,)
            self.leg_stroke = response.leg_stroke
            self.hand_stroke = response.hand_stroke

            # Report the receipt of data
            self.get_logger().info('Received geometry data!')

            # Record the receipt of data so that we know we've got it
            self.has_geometry_data = True
        else:
            self.get_logger().error('Exception while calling "get_robot_geometry" service')

    def pose_callback(self, msg):
        if self.has_geometry_data:
            # Extract position data
            pos = np.array([[msg.position.x], [msg.position.y], [msg.position.z]])

            # Extract the orientation quaternion
            orientation_q = msg.orientation
            quaternion = [orientation_q.x, orientation_q.y, orientation_q.z, orientation_q.w]
            
            # Convert quaternion to 4x4 rotation matrix
            rot = tf_transformations.quaternion_matrix(quaternion)

            # Extract the 3x3 rotation matrix
            rot = rot[:3, :3]

            # Use this data to update the locations of all the platform nodes
            self.update_pose(pos, rot)

    def update_pose(self, pos, rot):
        # Calculate the positions of all nodes

        new_position = pos + self.start_pos

        # Update plat_nodes to reflect change in pose
        self.new_plat_nodes = (new_position + np.dot(rot, self.init_plat_nodes.T)).T

        # Calculate leg lengths
        leg_lengths_mm = np.linalg.norm(self.new_plat_nodes - self.base_nodes, axis=1) - self.init_leg_lengths

        ''' 
        Remainder serves to determine the positions of the hand nodes. This isn't strictly necessary for this node, but may
        come in handy later?
        '''
        # # Update arm nodes
        # self.new_arm_nodes = (new_position + np.dot(rot, self.init_arm_nodes.T)).T

        # # Calculate the length of the hand string (leg 7)
        # string_length = np.linalg.norm(self.new_plat_nodes[6] - self.base_nodes[6])

        # # Update hand nodes
        # change_in_string_length = string_length - self.init_leg_lengths[-1]
        # self.unit_ori_vector = np.dot(rot, np.array([[0], [0], [1]]))
        # self.new_hand_nodes = ((new_position + np.dot(rot, self.init_hand_nodes.T)) +
        #                        change_in_string_length * self.unit_ori_vector ).T
        # self.hand_centroid = np.mean(self.new_hand_nodes, axis=0)

        # Send the data to be checked that it's within allowable limits
        self.check_leg_lengths(leg_lengths_mm)

    def check_leg_lengths(self, leg_lens_mm):
        # Check the leg lengths. Make sure they're within allowable bounds
        clipped_leg_lengths = np.clip(leg_lens_mm[:6], 0, self.leg_stroke)
        clipped_hand_length = np.clip(leg_lens_mm[6], -1000, self.hand_stroke)

        # Check if the arrays had to be changed. Log a warning or error if so
        if not np.array_equal(leg_lens_mm[:6], clipped_leg_lengths):
            self.get_logger().warn(f'Leg lengths had to be truncated!')

        if leg_lens_mm[6] != clipped_hand_length:
            self.get_logger().error(f'Hand string is overextended! Desired length: {leg_lens_mm[6]}')

        clipped_lengths = np.concatenate((clipped_leg_lengths, np.array([clipped_hand_length])))
        
        # Send the data off to be converted into revs
        self.convert_mm_to_revs(leg_lens_mm=clipped_lengths)

    def convert_mm_to_revs(self, leg_lens_mm):
        # Converts the leg lengths from mm to revs
        spool_dia = 22 # mm
        mm_to_rev = 1 / (spool_dia * np.pi)

        self.get_logger().debug(f'Leg lengths (mm): \n{leg_lens_mm}')
        leg_lengths_revs = [length * mm_to_rev for length in leg_lens_mm]

        # Send the data to be published
        self.publish_leg_lengths(leg_lengths_revs)

    def publish_leg_lengths(self, leg_lens_revs):
        leg_lengths = Float64MultiArray()
        leg_lengths.data = leg_lens_revs

        self.publisher.publish(leg_lengths)

def main(args=None):
    rclpy.init(args=args)
    node = SPInverseKinematics()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()
