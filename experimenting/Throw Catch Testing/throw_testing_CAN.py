import can
import cantools
import time
import math
import matplotlib.pyplot as plt
from ruckig import InputParameter, Trajectory, Result, Ruckig
from can_handler import CANHandler

def move_to_start_pos():
    # Set the hand gains to be the default values
    can_handler.set_hand_gains(pos_gain=18, vel_gain=0.008, vel_integrator_gain=0.01)

    # Put the motor into closed-loop control with POS_FILTER control mode
    can_handler._set_requested_state(axis_id=6, requested_state='CLOSED_LOOP_CONTROL')
    time.sleep(0.05)
    can_handler._set_control_mode(axis_id=6, control_mode='POSITION_CONTROL', input_mode='POS_FILTER')
    time.sleep(0.05)

    # Set the target position
    target_pos = lowest_pos
    can_handler.send_position_target(axis_id=6, setpoint=target_pos, max_position=throw_stroke)

    print(f'Start position: {target_pos:.2f}')

    # Wait for the motor to reach the target position
    while True:
        can_handler.fetch_messages()
        pos = can_handler.pos_values[6]
        # print(pos)
        if pos is not None:
            if abs(pos - target_pos) < 0.02:
                break
            time.sleep(0.01)

    
    # Now set the hand gains to be the throwing values
    can_handler.set_hand_gains(pos_gain=35, vel_gain=0.007, vel_integrator_gain=0.07)

    # And put the axis in PASSTHROUGH mode
    can_handler._set_control_mode(axis_id=6, control_mode='POSITION_CONTROL', input_mode='PASSTHROUGH')

def shutdown():
    # Put the motor into idle mode
    can_handler._set_requested_state(axis_id=6, requested_state='IDLE')

    # Close the CAN handler
    can_handler.close()

# All of this code will run on the hand motor, with axis id = 6

# Initialize the CAN handler
can_handler = CANHandler()

spool_dia_mm = 11.7
linear_gain = 1000 / (math.pi * spool_dia_mm)  # rev / m

stroke = 8.8    # revs (actually 8.867)
throw_stroke = 6 # revs
lowest_pos = (stroke - throw_stroke) / 2 # revs
highest_pos = lowest_pos + throw_stroke  # revs

release_pos = (lowest_pos + highest_pos) / 2 # revs

print(f'Linear gain: {linear_gain:.2f} rev/m, highest pos: {highest_pos:.2f} revs')

# For converting acceleration into torque
total_inertia_ref_to_hand = 0.37 # kg

# Set kinematic limits
max_vel = 15.0 * linear_gain # rev/s
max_accel = 50.0 * linear_gain # rev/s^2
max_jerk = 10000.0 * linear_gain # rev/s^3

print(f'Max vel: {max_vel:.2f} rev/s, max accel: {max_accel:.2f} rev/s^2, max jerk: {max_jerk:.2f} rev/s^3')

# Move to the start position
move_to_start_pos()
time.sleep(1.0)

# Set initial conditions
x0 = can_handler.pos_values[6]
v0 = 0.0
a0 = 0.0
t0 = 0.0
dt = 0.01

# Create lists for tracking (theoretical [th] and experimental [ex])
t = [t0]
x_th = [x0]
v_th = [v0]
a_th = [a0]
iq_set = [0.0]

x_ex = [x0]
v_ex = [can_handler.vel_values[6]]
iq_ex = [can_handler.iq_meas_values[6]]

# Create the Ruckig object
otg = Ruckig(1, dt)
inp = InputParameter(1)
trajectory = Trajectory(1)

inp.current_position = [x0]
inp.current_velocity = [v0]
inp.current_acceleration = [a0]

inp.target_position = [highest_pos]
inp.target_velocity = [0.0]
inp.target_acceleration = [0.0]

inp.max_velocity = [max_vel] # m/s
inp.max_acceleration = [max_accel]
inp.max_jerk = [max_jerk] # m/s^3

# Set different constraints for the negative direction (after ball has been thrown, we can decelerate faster)
# inp.min_velocity = [-max_vel * 1.5]
# inp.min_acceleration = [-max_accel * 1.5]

# Calculate the trajectory in an offline manner
result = otg.calculate(inp, trajectory)

# Check to make sure we have a valid input
if result == Result.ErrorInvalidInput:
    shutdown()
    raise Exception("Invalid input")

print(f'Trajectory duration: {trajectory.duration:.4f} s')

# Get some info about the position extrema of the trajectory
print(f'Position extrema are {trajectory.position_extrema[0]}')

throw_steps = 0
released = False
extra_time = 1.2 # We don't know the throw duration right now, so we'll just wait for a bit
return_step = 0
air_time = 0.0
delay_time = 0.0
first_wait_step = True

# Step through the trajectory and send the position commands, as well as logging the data
frames = int((trajectory.duration + extra_time) / dt)

for i in range(frames):
    # Get the most up-to-date data on what the motor is actually doing
    can_handler.fetch_messages()
    x_ex.append(can_handler.pos_values[6])
    v_ex.append(can_handler.vel_values[6])
    iq_ex.append(can_handler.iq_meas_values[6])
    iq_set.append(can_handler.iq_set_values[6])

    # If we're still inside the trajectory, get the theoretical values
    if i * dt < trajectory.duration:
        # Get the new position, velocity, and acceleration
        new_pos, new_vel, new_acc = trajectory.at_time(i * dt)
        throw_steps += 1
        
        # Find the maximum velocity and calculate the duration that the ball will be in the air
        if new_vel[0] > max(v_th):
            air_time = 2 * (new_vel[0] / linear_gain) / 9.81

    # Once we reach the end of the trajectory, wait for air_time before carrying out the trajectory in reverse (to catch - dodgily)
    elif i * dt < trajectory.duration + air_time + delay_time:
        # Do nothing
        if first_wait_step:
            # Set the hand gains low for the catch
            # can_handler.set_hand_gains(pos_gain=0.1, vel_gain=0.0001, vel_integrator_gain=0.01)
            first_wait_step = False
            pass
        return_step = i # Get the last step index before we start returning
        pass

    elif i * dt < 2 * trajectory.duration + air_time:
        # Get the new position, velocity, and acceleration
        traj_time = trajectory.duration - (i - return_step) * dt
        # print(traj_time)
        # print(f'Return step = {return_step}. i = {i}. Time = {traj_time:.4f} s')
        new_pos, new_vel, new_acc = trajectory.at_time(traj_time)
        new_vel[0] = -new_vel[0]

    else:
        # We're done
        pass

    # Log the data
    v_th.append(new_vel[0])
    a_th.append(new_acc[0])
    x_th.append(new_pos[0])
    t.append(i * dt)

    # Send the position command
    can_handler.send_arbitrary_message(axis_id=6, msg_name='set_input_pos', setpoint=new_pos[0])

    # Send the velocity FF command
    can_handler.send_arbitrary_message(axis_id=6, msg_name='set_input_vel', setpoint=new_vel[0])

    # Convert the acceleration into torque and send it
    torque = new_acc[0] * total_inertia_ref_to_hand * spool_dia_mm / 2000 # Nm. 2000 is converting dia (mm) to rad (m)
    can_handler.send_arbitrary_message(axis_id=6, msg_name='set_input_torque', setpoint=torque)
    
    time.sleep(dt)


max_v_th = max(v_th)
max_v_ex = max(v_ex)

print(f'Maximum theoretical velocity: {max_v_th:.2f} rev/s')
print(f'Maximum actual velocity: {max_v_ex:.2f} rev/s')

# Calculate throw stats
g = 9.81 # m/s^2
height = (max_v_th / linear_gain) ** 2 / (2 * g)
print(f'Throw height above release point: {height:.2f} m')

throw_duration = 2 * math.sqrt(2 * height / g)
print(f'Throw duration: {throw_duration:.2f} s')


shutdown()

# Plot the results on separate subfigures
plt.figure()

plt.subplot(4, 1, 1)
plt.title(f'One-stage throw test.\nRed line denotes end of throw\nPredicted throw height = {height:.2f} m')
plt.plot(t, x_th)
plt.plot(t, x_ex)
plt.legend(['Theoretical', 'Experimental'])
plt.ylabel('Position\n(revs)')
plt.axvline(x=throw_steps * dt, color='red', linestyle='dotted')
plt.grid()

plt.subplot(4, 1, 2)
plt.plot(t, v_th)
plt.plot(t, v_ex)
plt.legend(['Theoretical', 'Experimental'])
plt.ylabel('Velocity\n(revs / s)')
plt.axvline(x=throw_steps * dt, color='red', linestyle='dotted')
plt.grid()

plt.subplot(4, 1, 3)
plt.plot(t, a_th)
plt.ylabel('Acceleration\n(revs / s^2)')
plt.axvline(x=throw_steps * dt, color='red', linestyle='dotted')
plt.grid()

plt.subplot(4, 1, 4)
plt.plot(t, iq_set)
plt.plot(t, iq_ex)
plt.legend(['Setpoint', 'Measured'])
plt.ylabel('Iq')
plt.axvline(x=throw_steps * dt, color='red', linestyle='dotted')
plt.grid()
plt.xlabel('Time (s)')

plt.show()