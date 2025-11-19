% smf_orchestration_flow.mzn
int: J; % Liczba regionów (źródła żądań)
int: K; % Liczba lokalizacji (węzły SMF)
int: R; % Typy zasobów

% --- Zasoby i Topologia ---
array[1..K, 1..R] of float: loc_resources;
array[1..R] of float: smf_req;              
array[1..J, 1..K] of bool: connected;       

% --- Dane o ruchu (Popyt) ---
array[1..J] of int: pop;
array[1..J] of float: req_per_person;
float: tau;

% Obliczenie całkowitej liczby sesji generowanej przez każdy region
array[1..J] of float: active_sessions = [ pop[j] * req_per_person[j] * tau | j in 1..J ];

array[1..K,1..J] of float: latency_kj; 
float: Lmax;
int: C; % Pojemność jednej instancji (liczba sesji)
int: Nmin;
float: cost_per_instance;

% --- Wagi optymalizacji ---
float: weight_cost;    
float: weight_latency; 
float: weight_balance;

% --- Limity domen (optymalizacja solvera) ---
array[1..K] of int: max_cap = [ min([ floor(loc_resources[k,r] / smf_req[r]) | r in 1..R ]) | k in 1..K ];
int: system_max_cap = max(max_cap);

% --- ZMIENNE DECYZYJNE ---

% x: Liczba instancji w lokalizacji k
array[1..K] of var 0..system_max_cap: x;

% flow[j,k] - zmienna, która zapisuje "skąd idzie ile żądań". 
% Mówi nam, ile sesji z regionu J jest obsługiwanych przez węzeł K.
% To nasza zmienna "y"
array[1..J,1..K] of var 0.0..max(active_sessions): flow;

% Wykorzystanie do balansowania
var 0.0..1.0: max_util;

% --- OGRANICZENIA ---

% 1. Obsługa całego ruchu (Conservation of Flow)
% Wszystkie sesje wygenerowane w regionie J muszą zostać gdzieś obsłużone.
constraint forall(j in 1..J) (
    sum(k in 1..K)(flow[j,k]) = active_sessions[j]
);

% 2. Latency & Connectivity
% Ruch może płynąć tylko tam, gdzie jest połączenie i akceptowalne opóźnienie.
constraint forall(j in 1..J, k in 1..K) (
    if flow[j,k] > 0.0 then
        connected[j,k] = true /\ latency_kj[k,j] <= Lmax
    endif
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

constraint forall(k in 1..K)( x[k] >= Nmin );

% 4. LOAD BALANCING (Balansowanie obciążenia)
% Jeśli w danej lokalizacji nie ma instancji (x[k]=0), to max_util nie ma znaczenia dla tego k.
% Jeśli są instancje, to ich wypełnienie nie może przekroczyć max_util.
constraint forall(k in 1..K)(
    if x[k] > 0 then
        sum(j in 1..J)( flow[j,k] ) <= max_util * (x[k] * C)
    else
        sum(j in 1..J)( flow[j,k] ) = 0.0
    endif
);

% --- FUNKCJA CELU ---

% A. Koszt (Infrastruktura)
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );

% B. Latency (Średnie ważone opóźnienie)
% Sumujemy (Ilość ruchu * Opóźnienie) i dzielimy przez całkowitą liczbę sesji.
float: total_system_sessions = sum(active_sessions);
var float: global_latency_sum = sum(j in 1..J, k in 1..K)(
    flow[j,k] * latency_kj[k,j]
);
var float: avg_latency = global_latency_sum / total_system_sessions;

solve minimize 
    (weight_cost * total_cost) + 
    (weight_latency * avg_latency) + 
    (weight_balance * max_util * 100);

% --- ZAAWANSOWANE RAPORTOWANIE ---

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