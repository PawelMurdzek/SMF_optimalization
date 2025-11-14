% smf_orchestration_balanced.mzn

int: J; 
int: K; 
int: R; 

% --- Resources & Topology ---
array[1..K, 1..R] of float: loc_resources;  
array[1..R] of float: smf_req;              
array[1..J, 1..K] of bool: connected;       

% --- Standard Data ---
array[1..J] of int: pop;
array[1..J] of float: req_per_person;
float: tau;
array[1..J] of float: active_sessions = [ pop[j] * req_per_person[j] * tau | j in 1..J ];

array[1..K,1..J] of float: latency_kj; 
float: Lmax;
int: C; 
int: Nmin;
float: cost_per_instance;

% --- Weights for Multi-Objective Optimization ---
float: weight_cost;    
float: weight_latency; 
float: weight_balance; 

% --- Decision Variables ---
% FIX: Added explicit upper bound (0..100) to prevent 'Number out of limits' error
array[1..K] of var 0..100: x;             
array[1..J,1..K] of var 0..1: assign;
var 0.0..1.0: max_util; 

% --- Constraints ---

% 1. Assignment & Connectivity
constraint forall(j in 1..J) ( sum(k in 1..K)(assign[j,k]) = 1 );
constraint forall(j in 1..J, k in 1..K) ( assign[j,k] = 1 -> latency_kj[k,j] <= Lmax );
constraint forall(j in 1..J, k in 1..K) ( assign[j,k] = 1 -> connected[j,k] = true );

% 2. Capacity & Resources
constraint forall(k in 1..K)(
    sum(j in 1..J)( assign[j,k] * active_sessions[j] ) <= x[k] * C
);
constraint forall(k in 1..K, r in 1..R)(
    x[k] * smf_req[r] <= loc_resources[k,r]
);
constraint forall(k in 1..K)( x[k] >= Nmin );

% 3. LOAD BALANCING CONSTRAINT
% Forces max_util to be >= the utilization of the busiest server
% Note: We multiply x[k] * C * max_util. Since x is now bounded, this is safe.
constraint forall(k in 1..K)(
    sum(j in 1..J)( assign[j,k] * active_sessions[j] ) <= max_util * (x[k] * C)
);

% --- OBJECTIVE FUNCTION ---

% A. Cost
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );

% B. Latency
float: total_sessions = sum(active_sessions);
var float: avg_latency = sum(j in 1..J, k in 1..K)(
    assign[j,k] * active_sessions[j] * latency_kj[k,j]
) / total_sessions;

% C. Balance (Utilization)
solve minimize 
    (weight_cost * total_cost) + 
    (weight_latency * avg_latency) + 
    (weight_balance * max_util * 100); 

output [
  "--- RESULTS ---\n",
  "Instances (x): " ++ show(x) ++ "\n",
  "Assignments: \n" ++ show2d(assign) ++ "\n",
  "Peak Utilization: " ++ show(max_util * 100) ++ "%\n",
  "--- METRICS ---\n",
  "Total Cost: " ++ show(total_cost) ++ "\n",
  "Avg Latency: " ++ show(avg_latency) ++ "\n",
  "Objective Score: " ++ show((weight_cost * total_cost) + (weight_latency * avg_latency) + (weight_balance * max_util * 100)) ++ "\n"
];