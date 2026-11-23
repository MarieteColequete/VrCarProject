class_name DriverModel
extends RefCounted
## How a road user follows what is ahead of it, over plain numbers: the Intelligent Driver Model's
## acceleration, whether something ahead forces a reaction, and the deceleration stopping short of
## it needs. Static and pure, for worker threads; [AgentTable] calls it with a row's columns.


## Whether something [param gap] metres ahead, moving at [param ahead_speed], forces a reaction at
## speed [param v] for a driver keeping [param min_gap]: it is within the gap kept at a reaction's
## headway, or closing so fast that keeping the script would need braking.
static func forced(min_gap: float, gap: float, ahead_speed: float, v: float) -> bool:
	if gap <= min_gap + v * 0.5:
		return true
	var closing := v - ahead_speed
	if closing <= 0.0:
		return false
	return closing * closing / (2.0 * maxf(gap - min_gap, 0.01)) > 0.5


## The deceleration that stopping short of what is ahead, keeping [param min_gap], needs at speed
## [param v]; 0 when it is not closing in.
static func needed_decel(min_gap: float, v: float, gap: float, ahead_speed: float) -> float:
	var closing := v - ahead_speed
	if closing <= 0.0:
		return 0.0
	return closing * closing / (2.0 * maxf(gap - min_gap, 0.1))


## The Intelligent Driver Model's acceleration at speed [param v] behind what is [param gap]
## metres ahead at [param ahead_speed], towards [param target], for a driver keeping
## [param min_gap] and [param headway] seconds, accelerating at most [param accel], braking
## comfortably at [param comfort] and at most at [param most_decel].
static func idm(v: float, gap: float, ahead_speed: float, target: float, min_gap: float,
		headway: float, accel: float, comfort: float, most_decel: float) -> float:
	var closing := v - ahead_speed
	var wanted := min_gap + maxf(0.0, v * headway + v * closing / (2.0 * sqrt(accel * comfort)))
	var g := maxf(gap, 0.05)
	var free := 1.0 - pow(v / maxf(target, 0.1), 4.0)
	return maxf(accel * (free - (wanted / g) * (wanted / g)), -most_decel)
