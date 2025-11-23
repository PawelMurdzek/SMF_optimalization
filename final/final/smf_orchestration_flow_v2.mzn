% smf_orchestration_flow_full.mzn
% Model MiniZinc łączący model optymalizacyjny z danymi wejściowymi.

% --- WEJŚCIE I DANE (Data Section) ---

int: J = 5; % Liczba regionów (źródła żądań)
int: K = 3; % Liczba lokalizacji (węzły SMF)
int: R = 3; % Typy zasobów

% Wymagania zasobowe na 1 instancję SMF (CPU (Rdzenie), RAM (GB), SSD (GB))
array[1..R] of float: smf_req = [2.0, 4.0, 10.0]; 

% --- ZASOBY W LOKALIZACJACH (LOC_RESOURCES) ---
array[1..K, 1..R] of float: loc_resources = array2d(1..K, 1..R, [ 
    30.0,  96.0,  300.0,  % Lokalizacja 1 (Frankfurt)
    120.0, 384.0, 1500.0, % Lokalizacja 2 (Ashburn)
    60.0,  192.0, 600.0   % Lokalizacja 3 (Singapur)
]);

% --- POŁĄCZENIA (CONNECTIVITY) ---
array[1..J, 1..K] of bool: connected = array2d(1..J, 1..K, [
    true,  false, true,  % Region 1 (Europa Zach.)
    false, true,  true,  % Region 2 (Ameryka Płn.)
    true,  true,  true,  % Region 3 (Azja Wschodnia)
    true,  true,  false, % Region 4 (Ameryka Połud.)
    true,  true,  true   % Region 5 (Europa Cent.)
]);

% --- POPULACJA I SESJE (WYMAGANIA) ---
array[1..J] of int: pop = [80000, 120000, 50000, 30000, 100000]; 
array[1..J] of float: req_per_person = [0.002, 0.003, 0.0015, 0.0025, 0.001]; 
float: tau = 600.0; 

% --- OPÓŹNIENIA (LATENCY) [Lokalizacja, Region] ---
array[1..K,1..J] of float: latency_kj = array2d(1..K, 1..J, [ 
     10.0,  80.0, 180.0, 150.0, 20.0,  % Lok 1 (Frankfurt)
     70.0,  20.0, 150.0,  90.0, 80.0,  % Lok 2 (Ashburn)
    180.0, 150.0,  30.0, 220.0, 170.0  % Lok 3 (Singapur)
]);

float: Lmax = 100.0; % Ograniczenie opóźnienia
int: C = 50000;    % Pojemność jednej instancji (sesje)
int: Nmin = 1;     % Wymóg minimum 1 instancji dla redundancji
float: cost_per_instance = 1.0; 

% --- KONFIGURACJA WAG FUNKCJI CELU ---
float: weight_cost = 10.0;     
float: weight_latency = 50.0;  
float: weight_balance = 0.0; 

% --- PRZELICZANE PARAMETRY ---

% Obliczenie całkowitej liczby sesji generowanej przez każdy region
array[1..J] of float: active_sessions = [ pop[j] * req_per_person[j] * tau | j in 1..J ];

% Maksymalna pojemność zasobowa dla każdej lokalizacji
array[1..K] of int: max_cap = [ min([ floor(loc_resources[k,r] / smf_req[r]) | r in 1..R ]) | k in 1..K ];
int: system_max_cap = max(max_cap);
float: max_flow = max(active_sessions) * 1.1; % Bezpieczny górny limit dla zmiennej flow

% POMOCNICZY PARAMETR DLA ZEROWANIA NIEDOZWOLONEGO RUCHU (Poprawiony składniowo)
% Jest 1.0, jeśli połączenie jest możliwe (connected=true ORAZ latency<=Lmax). Inaczej 0.0.
array[1..J, 1..K] of float: flow_limiter = array2d(1..J, 1..K,
    [ connected[j,k] * (latency_kj[k,j] <= Lmax)
      | j in 1..J, k in 1..K 
    ]);

% --- ZMIENNE DECYZYJNE ---

% x: Liczba instancji w lokalizacji k
array[1..K] of var 0..system_max_cap: x;

% flow[j,k] - ile sesji z regionu J jest obsługiwanych przez węzeł K.
array[1..J,1..K] of var 0.0..max_flow: flow; 

% Wykorzystanie do balansowania
var 0.0..1.0: max_util;

% --- OGRANICZENIA BEZ IF-ELSE ---

% 1. Obsługa całego ruchu (Conservation of Flow)
% Wszystkie sesje wygenerowane w regionie J muszą zostać gdzieś obsłużone.
constraint forall(j in 1..J) (
    sum(k in 1..K)(flow[j,k]) = active_sessions[j]
);

% 2. Latency & Connectivity (NOWA WERSJA BEZ IF)
% Ruch może płynąć tylko tam, gdzie flow_limiter jest 1.0 (pozwolone połączenie).
constraint forall(j in 1..J, k in 1..K) (
    flow[j,k] <= max_flow * flow_limiter[j,k]
);

% 3. Pojemność i Zasoby (Capacity)
% Suma ruchu wpadającego do lokalizacji K nie może przekroczyć pojemności postawionych tam instancji.
constraint forall(k in 1..K)(
    sum(j in 1..J)( flow[j,k] ) <= x[k] * C
);

% Ograniczenia fizyczne zasobów (CPU/RAM) na lokalizację
constraint forall(k in 1..K, r in 1..R)(
    x[k] * smf_req[r] <= loc_resources[k,r]
);

% Minimalna liczba instancji dla HA/odporności 
constraint forall(k in 1..K)( x[k] >= Nmin ); 

% 4. LOAD BALANCING (Balansowanie obciążenia) (NOWA WERSJA BEZ IF)
% Definiuje zmienną max_util jako maksymalne wypełnienie *pojemności* w każdej lokalizacji.
constraint forall(k in 1..K)(
    sum(j in 1..J)( flow[j,k] ) <= max_util * (x[k] * C)
);

% --- FUNKCJA CELU ---

% A. Koszt (Infrastruktura)
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );

% B. Latency (Średnie ważone opóźnienie)
float: total_system_sessions = sum(active_sessions);
var float: global_latency_sum = sum(j in 1..J, k in 1..K)(
    flow[j,k] * latency_kj[k,j]
);
var float: avg_latency = global_latency_sum / total_system_sessions;

% Minimalizacja ważonej sumy kosztów, opóźnienia i maksymalnego wykorzystania.
solve minimize 
    (weight_cost * total_cost) + 
    (weight_latency * avg_latency) + 
    (weight_balance * max_util * 100);

% --- RAPORTOWANIE ---

output [
  "======================================================\n",
  "=== RAPORT ALOKACJI SMF (SFLOW MODEL) ===\n",
  "======================================================\n",
  "1. KONFIGURACJA ZASOBÓW\n",
  "   Liczba Regionów (J): " ++ show(J) ++ "\n",
  "   Liczba Lokalizacji (K): " ++ show(K) ++ "\n",
  "   Wagi (Koszt/Opóźnienie/Balans): " ++ show(weight_cost) ++ " / " ++ show(weight_latency) ++ " / " ++ show(weight_balance) ++ "\n\n",

  "2. ROZMIESZCZENIE INSTANCJI (Zmienna x)\n"
] ++
[
  "   Lokalizacja " ++ show(k) ++ ": " ++ show(x[k]) ++ " instancji (Max Cap: " ++ show(x[k]*C) ++ " sesji)\n"
  | k in 1..K
] ++
[
  "\n3. SZCZEGÓŁOWY PRZEPŁYW RUCHU (Flow)\n",
  "   (Skąd -> Dokąd : Ilość Sesji | Opóźnienie)\n"
] ++
[
  if fix(flow[j,k]) > 0.0 then
    "   Region " ++ show(j) ++ " -> SMF " ++ show(k) ++ 
    " : " ++ show_float(6, 1, flow[j,k]) ++ " sesji | " ++ show(latency_kj[k,j]) ++ "ms\n"
  else "" endif
  | j in 1..J, k in 1..K
] ++
[
  "\n4. METRYKI KOŃCOWE\n",
  "   Szczytowe zużycie (Max Util): " ++ show_float(4, 2, max_util * 100) ++ "%\n",
  "   Średnie opóźnienie (Avg Latency): " ++ show_float(4, 2, avg_latency) ++ " ms\n",
  "   Całkowity koszt (Total Cost): " ++ show_float(8, 2, total_cost) ++ "\n",
  "   Funkcja celu (Objective): " ++ show((weight_cost * total_cost) + (weight_latency * avg_latency) + (weight_balance * max_util * 100)) ++ "\n",
  "======================================================\n"
];

% --- SEKCJA CSV DLA EXCELA ---
output [
  "\n--- DANE CSV (Kopiuj do Excela) ---\n",
  "Region;Lokalizacja;Ilosc_Sesji;Opoznienie;Koszt_Instancji\n"
] ++
[
  if fix(flow[j,k]) > 0.0 then
    show(j) ++ ";" ++ show(k) ++ ";" ++ show(flow[j,k]) ++ ";" ++ show(latency_kj[k,j]) ++ ";" ++ show(cost_per_instance) ++ "\n"
  else "" endif
  | j in 1..J, k in 1..K
];