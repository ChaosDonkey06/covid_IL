covid_source('utils.R')
library(stringr)
#' Simulate COVID pomp model
simulate_pomp_covid <- function(
  n_age_groups,
  n_regions,
  nsim, 
  input_params, 
  delta_t, 
  population_list, 
  beta_scales,
  beta_covar,
  contacts,
  frac_underreported,
  seed = NULL,
  format = 'data.frame',
  rprocess_Csnippet,
  initialize = T,
  rinit_Csnippet,
  rmeasure_Csnippet=NULL,
  obsnames = NULL,
  initial_params = NULL
) {
  library(pomp)
  
  # Initialize states
  subcompartment_df <- simulate_pomp_covid__init_subcompartment_df(input_params)

  # Set up parameters for pomp
  params <- simulate_pomp_covid__init_parameters(
    n_age_groups, input_params, population_list
  )

  # Set up covariate table for pomp
  covar_table_interventions <- simulate_pomp_covid__init_covariate_table(
    input_params, beta_scales, beta_covar, frac_underreported, contacts
  )

  covar_table <- covariate_table(
    covar_table_interventions,
    order = "constant",
    times = "time"
  )

  # Actually call pomp
  state_names <- simulate_pomp_covid__init_state_names(n_age_groups, n_regions, subcompartment_df)
  
  ## Set up accumulator variables by age group and then by regions
  acc_new_symptomatic <- sprintf("new_symptomatic_infections_%d",c(1:n_age_groups))
  acc_nD <- sprintf("new_deaths_%d",c(1:n_age_groups))
  acc_nHD <- sprintf("new_hosp_deaths_%d",c(1:n_age_groups))
  acc_nNHD <- sprintf("new_nonhosp_deaths_%d", c(1:n_age_groups))
  acc_nH <- sprintf("new_hospitalizations_%d", c(1:n_age_groups))
  acc_INC <- sprintf("Inc_%d", c(1:n_age_groups))
  
  accum_names <- array()
  for(i in c(1:n_regions)){
    accum_names <- c(accum_names, paste0(acc_new_symptomatic, "_", i))
  }
  for(i in c(1:n_regions)){
    accum_names <- c(accum_names, paste0(acc_nD, "_", i))
  }
  for(i in c(1:n_regions)){
    accum_names <- c(accum_names, paste0(acc_nHD, "_", i))
  }
  for(i in c(1:n_regions)){
    accum_names <- c(accum_names, paste0(acc_nNHD, "_", i))
  }
  for(i in c(1:n_regions)){
    accum_names <- c(accum_names, paste0(acc_nH, "_", i))
  }
  for(i in c(1:n_regions)){
    accum_names <- c(accum_names, paste0(acc_INC, "_", i))
  }
  
  accum_names <- accum_names[!is.na(accum_names)]
  times <- c(ceiling(input_params$tmin):ceiling(input_params$tmax)) 
  
  if(initialize == T){
  print('Simulating')
  output_df <- simulate(
    nsim = nsim,
    seed = seed,
    times = times,
    t0 = times[1],
    rinit = rinit_Csnippet,
    rprocess = euler(rprocess_Csnippet, delta.t = delta_t),
    rmeasure = rmeasure_Csnippet,
    
    params = params,
    covar = covar_table,
    
    statenames = c(state_names, accum_names),
    paramnames = names(params),
    accumvars = accum_names,
    obsnames = obsnames,
    format = format
  )
  print('Simulation finished')
  #print(params)
  }
  if(initialize == F){
    output_df <- simulate(
      nsim = 1,
      seed = seed,
      times = times,
      t0 = times[1],
      rprocess = euler(rprocess_Csnippet, delta.t = delta_t),
      rmeasure = rmeasure_Csnippet,
      
      params = c(params, initial_params),
      covar = covar_table,
      
      statenames = c(state_names, accum_names),
      paramnames = names(params),
      accumvars = accum_names,
      obsnames = obsnames,
      format = format
    )
  }
  list(
    n_age_groups = n_age_groups,
    raw_simulation_output = output_df,
    params = params,
    state_names = state_names,
    interventions = covar_table_interventions
  )
}

simulate_pomp_covid__init_subcompartment_df <- function(input_params) {
  with(input_params, {
    data.frame(
      state = c("E","A","P","IM","IM_dead","IS", "IH1_", "IH2_", "IH3_", "IC2_", "IC3_", "IH4_"),
      index = c(
        alpha_E,
        alpha_A, alpha_P,
        alpha_IM, alpha_IM,
        alpha_IS,
        alpha_IH1, alpha_IH2, alpha_IH3,
        alpha_IC2, alpha_IC3,
        alpha_IH4
      )
    )
  })
}

simulate_pomp_covid__init_state_names <- function(n_age_groups, n_regions, subcompartment_df) {
  ## State variables with variable classes per age group
  state_names_S_age = c(sprintf("S_%d",c(1:n_age_groups)))
  state_names_R_age = c(sprintf("R_%d",c(1:n_age_groups)))
  state_names_D_age <- c(sprintf("D_%d",c(1:n_age_groups)))

  state_names_S <- array()
  state_names_R <- array()
  state_names_D <- array()

  for(i in c(1:n_regions)){
    state_names_S <- c(state_names_S, paste0(state_names_S_age, "_", i))
    state_names_R <- c(state_names_R, paste0(state_names_R_age, "_", i))
    state_names_D <- c(state_names_D, paste0(state_names_D_age, "_", i))
  }
    
  state_names <- c(state_names_S, state_names_R, state_names_D)

  for(i in c(1:nrow(subcompartment_df))) {
      state_var = as.character(subcompartment_df[i,]$state)
      n_subcompartments = subcompartment_df[i,]$index
      state_names_var_age <- array()
      for(k in c(1:n_age_groups)){
        for(j in c(1:n_subcompartments)) {
          state_names_var_age = c(state_names_var_age, paste0(state_var,j,"_",k))
        }
      }
      state_names_var_age <- state_names_var_age[!is.na(state_names_var_age)]
      state_names_var_age_region <- array()
      for(z in c(1:n_regions)){
         state_names_var_age_region <- c(state_names_var_age_region, paste0(state_names_var_age,"_",z))
      }
      state_names_var_age_region <- state_names_var_age_region[!is.na(state_names_var_age_region)]
      state_names <- c(state_names, state_names_var_age_region)
  }

  state_names <- state_names[!is.na(state_names)]
  state_names
}


simulate_pomp_covid__init_parameters <- function(
  n_age_groups, input_params, population_list
) {
  with(input_params, {
    # Set up parameters for model
    params = c(
      "n_age_groups" = n_age_groups,
      "n_regions" = n_regions,
      "region_to_test" = region_to_test,
      "sigma" = 1/inv_sigma,
      "eta" = 1/inv_eta,
      "zeta_s" = 1/inv_zeta_s,
      "mu_m" = 1/inv_mu_m,
      "gamma_m" = 1/inv_gamma_m,
      'mu_h' = 1/inv_mu_h,
      "zeta_h_max" = zeta_h_max,
      "zeta_h_min" = zeta_h_min,
      "zeta_h_logit" = zeta_h_logit,
      "gamma_c" = 1/inv_gamma_c,
      "alpha_E"= alpha_E,
      "alpha_P"= alpha_P,
      "alpha_A"= alpha_A,
      "alpha_IM"= alpha_IM,
      "alpha_IS"= alpha_IS,
      "alpha_IH1" = alpha_IH1, 
      "alpha_IH2" = alpha_IH2,
      "alpha_IH3" = alpha_IH3, 
      "alpha_IC2" = alpha_IC2,
      "alpha_IC3" = alpha_IC3,
      "alpha_IH4" = alpha_IH4

    )
    
    # Age-specific parameters
    params[paste0("rho_",c(1:n_age_groups))] = unlist(
      input_params[paste0('rho_', c(1:n_age_groups))]
    )
    params[paste0("IHR_logit_",c(1:n_age_groups))] = unlist(
      input_params[paste0('IHR_logit_', c(1:n_age_groups))]
    )
    params[paste0("IHR_min_",c(1:n_age_groups))] = unlist(
      input_params[paste0('IHR_min_', c(1:n_age_groups))]
    )
    params[paste0("IHR_max_",c(1:n_age_groups))] = unlist(
      input_params[paste0('IHR_max_', c(1:n_age_groups))]
    )
    params[paste0("q_",c(1:n_age_groups))] = unlist(
      input_params[paste0('q_', c(1:n_age_groups))]
    )
    params[paste0("age_beta_scales_",c(1:n_age_groups))] = unlist(
      input_params[paste0('age_beta_scales_', c(1:n_age_groups))]
    )
    params[paste0("zeta_c_",c(1:n_age_groups))] = unlist(
        1/unlist(input_params[paste0('inv_zeta_c_', c(1:n_age_groups))])
    )
    params[paste0("mu_c_",c(1:n_age_groups))] = unlist(
        1/unlist(input_params[paste0('inv_mu_c_', c(1:n_age_groups))])
    )
    params[paste0("gamma_h_",c(1:n_age_groups))] = unlist(
        1/unlist(input_params[paste0('inv_gamma_h_', c(1:n_age_groups))])
    )

    params[paste0("psi1_",c(1:n_age_groups))] = unlist(
      input_params[paste0('psi1_', c(1:n_age_groups))]
    )
    params[paste0("psi2_",c(1:n_age_groups))] = unlist(
      input_params[paste0('psi2_', c(1:n_age_groups))]
    )
    params[paste0("psi3_",c(1:n_age_groups))] = unlist(
      input_params[paste0('psi3_', c(1:n_age_groups))]
    )
    params[paste0("psi4_",c(1:n_age_groups))] = unlist(
      input_params[paste0('psi4_', c(1:n_age_groups))]
    )

    # Region-specific parameters
    params[paste0("num_init_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('num_init_', c(1:n_regions))])
      )     
    params[paste0("beta1_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('beta1_', c(1:n_regions))])
      )     
    if (use_changepoint){ # Only add these parameters if you're using a changepoint model
      params[paste0("beta2_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('beta2_', c(1:n_regions))])
      )     
      params[paste0("t_phase3_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('t_phase3_', c(1:n_regions))])
      )
      params[paste0("t_phase3_max_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('t_phase3_max_', c(1:n_regions))])
      )
      params[paste0("scale_phase3_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('scale_phase3_', c(1:n_regions))])
      )
      params[paste0("t_phase4_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('t_phase4_', c(1:n_regions))])
      )
      params[paste0("t_phase4_max_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('t_phase4_max_', c(1:n_regions))])
      )
      params[paste0("scale_phase4_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('scale_phase4_', c(1:n_regions))])
      )

      params[paste0("t_phase5_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('t_phase5_', c(1:n_regions))])
      )
      params[paste0("t_phase5_max_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('t_phase5_max_', c(1:n_regions))])
      )
      params[paste0("scale_phase5_",c(1:n_regions))] = unlist(
        unlist(input_params[paste0('scale_phase5_', c(1:n_regions))])
      )
    }
    n_regions_cons = 5
    params[paste0("region_non_hosp_", 1:n_regions_cons)] = unlist(
        unlist(input_params[paste0('region_non_hosp_', c(1:n_regions_cons))])
      )
    for(i in c(1:n_regions_cons)){
      params[paste0(paste0("age_dist_",c(1:n_age_groups)),"_",i)] = input_params[sprintf('age_dist_%s_%s', c(1:n_age_groups), i)]
    }

    # age and region
    for(i in c(1:n_regions)){
      params[paste0(paste0("N_",c(1:n_age_groups)),"_",i)] = population_list %>% filter(covid_region == i) %>% select(POPULATION) %>% unlist(use.names=F)
    }

    
    params
  })
}

simulate_pomp_covid__init_covariate_table <- function(input_params, 
  beta_scales,
  beta_covar,
  frac_underreported,
  contacts) {
    
    covar_table_interventions <- data.frame(time = c(1:input_params$tmax))
  
  for (region in 1:input_params$n_regions){
      col = paste0('frac_underreported_',region)
      covar_table_interventions[[col]] = frac_underreported[covar_table_interventions$time, col]
  }
  for (region in 1:input_params$n_regions){
      col_se = paste0('frac_underreported_se_',region)
      covar_table_interventions[[col_se]] = frac_underreported[covar_table_interventions$time, col_se]
  }

  if (!is.null(beta_scales)){

    for (region in 1:input_params$n_regions){
        col = paste0(beta_covar, '_', region)
        model_colname = paste0('scale_beta_', region)
        covar_table_interventions[[model_colname]] = beta_scales[covar_table_interventions$time, col]
    }
  }
  if (!is.null(contacts)){
      covar_table_interventions = left_join(covar_table_interventions, contacts, by='time')
  }
  covar_table_interventions
}

#' Make output table with the following columns:
#' Simulation ID, Time, Compartment, Age group, Cases
 
process_pomp_covid_output <- function(sim_result, agg_regions=T) {
  n_age_groups <- sim_result$n_age_groups
  df_sim <- sim_result$raw_simulation_output
  print('Initial renaming')
  params <- sim_result$params
  print('Melting')
  df_sim_output <- df_sim %>% 
      melt(id.vars = c(".id", "time")) %>% 
      rename(
          Compartment = variable,
          Cases = value
      )
  print('Made it')
  df_sim_output %>% mutate(Region=word(Compartment, -1, sep='_'),
    Compartment = case_when(
      startsWith(as.character(Compartment), "S") ~ "S",
      startsWith(as.character(Compartment), "E") ~ "E",
      startsWith(as.character(Compartment), "P") ~ "P",
      startsWith(as.character(Compartment), "A") ~ "A",
      startsWith(as.character(Compartment), "IS") ~ "IS",
      startsWith(as.character(Compartment), "IM") ~ "IM",
      startsWith(as.character(Compartment), "IH") ~ "IH",
      startsWith(as.character(Compartment), "IC") ~ "IC",
      startsWith(as.character(Compartment), "R") ~ "R",
      startsWith(as.character(Compartment), "D") ~ "D",
      startsWith(as.character(Compartment), "ObsDeaths") ~ "Reported deaths",
      startsWith(as.character(Compartment), "Inc") ~ "Incidence",
      startsWith(as.character(Compartment), "new_deaths") ~ "nD",
      startsWith(as.character(Compartment), "new_hosp_deaths") ~ "nHD",
      startsWith(as.character(Compartment), "new_nonhosp_deaths") ~ "nNHD",
      startsWith(as.character(Compartment), "new_hospitalizations") ~ 'new_hospitalizations',
      startsWith(as.character(Compartment), "new_symptomatic") ~ "nS",
      startsWith(as.character(Compartment), "ObsICU") ~ "ObsICU",
      startsWith(as.character(Compartment), "ObsHosp_") ~ "ObsHosp",
      startsWith(as.character(Compartment), "ObsHospDeaths_") ~ "ObsHospDeaths",
  )
  ) -> df_sim_output

  names(df_sim_output) = c('SimID', 'Time', 'Compartment', 'Cases', 'Region')

  if (agg_regions){
      df_sim_output %>%
        group_by(SimID, Time, Compartment) %>%
        summarize(Cases = sum(Cases)) -> df_sim_output
    } else{
      df_sim_output %>%
        group_by(SimID, Time, Compartment, Region) %>%
        summarize(Cases = sum(Cases)) -> df_sim_output
    }

  c(
    sim_result,
    list(plotting_output = df_sim_output)
  )
}

format_for_covid_hub <- function(plotting_output,
  FIPS_code=17,
  forecast_date=Sys.Date()){

  library(purrr)
  library(tidyverse)
  get_target_name <- function(date, forecast_date, compartment){
      days_ahead = as.numeric(date - forecast_date)
      name = sapply(compartment, FUN=function(x){ifelse(x=='D', 'cum death', ifelse(x=='nD', 'inc death', 'inc hosp'))})
      target = sprintf("%s day ahead %s", days_ahead, name)
      return(target)
  }

  p <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
  p_names <- map_chr(p, ~.x)
  p_funs <- map(p, ~partial(quantile, probs = .x, na.rm = TRUE)) %>% 
    set_names(nm = p_names)
  p_funs$`NA` = function(.x){mean(.x)}

  plotting <- as.data.frame(plotting_output)
  plotting <- plotting %>% mutate(Time=as.Date('2020-01-14') + Time)
  quantiles = plotting %>% group_by(Time, Compartment) %>% 
      summarize_at(vars(Cases), funs(!!!p_funs)) %>%
      ungroup() %>%
      filter(Time > forecast_date, Compartment %in% c('D', 'nD', 'H'))

  final_frame <- quantiles %>%     
    gather('quantile', 'value', 3:ncol(quantiles)) %>%
    mutate(location=FIPS_code,
             location_name='Illinois',
             forecast_date=forecast_date,
             type=case_when((quantile=='NA') ~'point',
                            (quantile!='NA') ~'quantile'),
             target=get_target_name(Time, forecast_date, Compartment),
             target_end_date=as.character(Time)
            ) %>%
    select('forecast_date','target','target_end_date','location','location_name','type','quantile','value')
  final_frame
}

format_for_covid_hub_week <- function(plotting_output,
  FIPS_code=17,
  forecast_date=Sys.Date()){

  library(purrr)
  library(tidyverse)
  get_target_name <- function(epi_week, epi_start_week, compartment){
      days_ahead = epi_week - epi_start_week
      name = sapply(compartment, FUN=function(x){ifelse(x=='D', 'cum death', ifelse(x=='nD', 'inc death', 'inc hosp'))})
      target = sprintf("%s wk ahead %s", days_ahead, name)
      return(target)
  }

  p <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
  p_names <- map_chr(p, ~.x)
  p_funs <- map(p, ~partial(quantile, probs = .x, na.rm = TRUE)) %>% 
    set_names(nm = p_names)
  p_funs$`NA` = function(.x){mean(.x)}

  plotting <- as.data.frame(plotting_output)%>% 
      mutate(Time=as.Date('2020-01-14') + Time, 
            Epiweek=MMWRweek(Time)$MMWRweek,
            weekday=weekdays(Time))
  
  incident_deaths <- plotting  %>% 
      filter(Compartment == 'nD') %>% 
      group_by(SimID, parset, Epiweek) %>% summarize(Cases=sum(Cases), Compartment='nD') %>% 
      select(SimID, parset, Epiweek, Compartment, Cases) %>% ungroup()

  cumulative_deaths <-  plotting %>% 
      filter(Compartment =='D', weekday=='Saturday') %>% 
      select(SimID, parset, Epiweek, Compartment, Cases)
  
  plotting = bind_rows(incident_deaths, cumulative_deaths)
  
  
   if (weekdays(forecast_date) %in% c('Sunday','Monday')){
      epi_start_week = MMWRweek(forecast_date)$MMWRweek - 1
  } else{
      epi_start_week = MMWRweek(forecast_date)$MMWRweek
  }
  
  quantiles = plotting %>% group_by(Epiweek, Compartment) %>% 
      summarize_at(vars(Cases), funs(!!!p_funs)) %>%
      ungroup() %>% 
      filter(Epiweek > epi_start_week, Compartment %in% c('D', 'nD'))
  


  final_frame <- quantiles %>%     
    gather('quantile', 'value', 3:ncol(quantiles)) %>%
    mutate(location=FIPS_code,
             location_name='Illinois',
             forecast_date=forecast_date,
             type=case_when((quantile=='NA') ~'point',
                            (quantile!='NA') ~'quantile'),
             target=get_target_name(Epiweek, epi_start_week, Compartment),
             target_end_date=sapply(Epiweek, FUN=function(x){as.character(MMWRweek2Date(2020, x, 7))})
            ) %>%
    select('forecast_date','target','target_end_date','location','location_name','type','quantile','value')
    final_frame
}

add_non_hospitalized_deaths = function(sim_full,
                                       pars,
                                       regional_aggregation=T,
                                       n_age_groups=9,
                                       n_regions=3){
  
  sim_raw_deaths_total <- sim_full$raw_simulation_output %>% select(contains(c("new_deaths")))
  sim_raw_deaths_hosp <- sim_full$raw_simulation_output %>% select(contains(c("new_hosp")))
  
  df_new_nonhosp_deaths <- data.frame(Time =sim_full$raw_simulation_output$time) %>%
    mutate(SimID = sim_full$raw_simulation_output$.id)
  
  # Make sure to loop over each region
  for (region in c(1:n_regions))
  {    
    for(i in c(1:n_age_groups)){
      df_new_nonhosp_deaths[,sprintf("NHD_%s_%s",i, region)] <- sim_raw_deaths_total[,sprintf('new_deaths_%s_%s', i, region)] - sim_raw_deaths_hosp[,sprintf('new_hosp_deaths_%s_%s', i, region)]
    }
  }
  df_new_nonhosp_deaths <- df_new_nonhosp_deaths %>%
    melt(id.vars = c("SimID", "Time")) %>%
    rename(
      Compartment = variable,
      Cases = value
    )
  df_new_nonhosp_deaths <-  df_new_nonhosp_deaths %>% mutate(Region=substr(Compartment, 
                                                                           nchar(as.character(Compartment)), 
                                                                           nchar(as.character(Compartment))),
                                                             Compartment = case_when(
                                                               startsWith(as.character(Compartment), "NHD") ~ "nDnH"))
  
  
  if(regional_aggregation){
    df_new_nonhosp_deaths <- df_new_nonhosp_deaths %>%
      group_by(SimID, Time, Compartment) %>% 
      summarize(Cases=sum(Cases)) %>% 
      ungroup()
    
    df_cum = df_new_nonhosp_deaths %>%
      group_by(SimID) %>% 
      arrange(Time) %>% 
      mutate(Cases = cumsum(Cases), 
             Compartment='DnH') %>% ungroup()
    df_non_hosp = bind_rows(df_new_nonhosp_deaths, df_cum)
    
  } else{
    
    df_cum = df_new_nonhosp_deaths %>%
      group_by(SimID, Region) %>% 
      arrange(Time) %>% 
      mutate(Cases = cumsum(Cases),
             Compartment='DnH') %>% ungroup()
    df_non_hosp = bind_rows(df_new_nonhosp_deaths, df_cum)
  }
  return(df_non_hosp)
}

get_reported_non_hospitalized_deaths = function(df_input,
                                                regional_aggregation,
                                                lower_bound_reporting = 0.25,
                                                upper_bound_reporting = 0.75){
  if(regional_aggregation){
     df_nHD <- df_input %>% 
    filter(Compartment == "nDnH") %>% 
    group_by(parset, SimID) %>% 
    mutate(Cases_reported = round(runif(1,lower_bound_reporting,upper_bound_reporting)*Cases)) %>% 
    ungroup() 
    } else{
         df_nHD <- df_input %>% 
          filter(Compartment == "nDnH") %>% 
          group_by(parset, SimID, Region) %>% 
    mutate(Cases_reported = round(runif(1,lower_bound_reporting,upper_bound_reporting)*Cases)) %>% 
    ungroup()   
    }
  return(df_nHD)
}

get_scale = function(t_logistic_start,
                     intervention_lift,
                     simstart,
                     simend,
                     max_scales){
    
    times = seq(1, simend, 1)
    
    logistic = function(x, mscale, shift=intervention_lift){
        mean = (mscale-1)/(1+exp(-(x - shift))) + 1
        mean
    }

    raw_scales = data.frame(time=times, 
                            scale_beta_1=logistic(times, mscale=max_scales[1]),
                            scale_beta_2=logistic(times, mscale=max_scales[2]),
                            scale_beta_3=logistic(times, mscale=max_scales[3]),
                            scale_beta_4=logistic(times, mscale=max_scales[4]),
                            scale_beta_5=logistic(times, mscale=max_scales[5])) %>%
        mutate(scale_beta_1 = case_when((time < t_logistic_start) ~1,
                                 (time>=t_logistic_start) ~scale_beta_1),
                scale_beta_2 = case_when((time < t_logistic_start) ~1,
                                                 (time>=t_logistic_start) ~scale_beta_2),
                scale_beta_3 = case_when((time < t_logistic_start) ~1,
                                                 (time>=t_logistic_start) ~scale_beta_3),
                scale_beta_4 = case_when((time < t_logistic_start) ~1,
                                                 (time>=t_logistic_start) ~scale_beta_4),
                scale_beta_5 = case_when((time < t_logistic_start) ~1,
                                                 (time>=t_logistic_start) ~scale_beta_5),
               add_noise_to_beta = case_when((time < t_logistic_start) ~ 0,
                                             (time >= t_logistic_start) ~ 1))
    
    row.names(raw_scales) = raw_scales$time
    raw_scales
    
}

get_scale_linear = function(
                     intervention_lift,
                     simstart,
                     simend,
                     max_scales,
                     tm = as.Date('2020-07-01')
                     ){
    
    times = seq(1, simend, 1)
    
    linear = function(x, mscale, tmax=as.Date(tm)){
        slope = (mscale - 1) / (as.numeric(tmax - as.Date('2020-01-14')) - intervention_lift)
        mean = slope * (x-intervention_lift) + 1
        mean = if_else(mean >= mscale, mscale, mean)
        mean
    }


    raw_scales = data.frame(time=times, 
                            scale_beta_1=1,
                            scale_beta_2=1,
                            scale_beta_3=1,
                            scale_beta_4=1,
                            scale_beta_5=1) %>%
        mutate(scale_beta_1 = case_when((time < intervention_lift) ~1,
                                                 (time>=intervention_lift) ~ linear(times, mscale=max_scales[1])),
                scale_beta_2 = case_when((time < intervention_lift) ~1,
                                                 (time>=intervention_lift) ~ linear(times, mscale=max_scales[2])),
                scale_beta_3 = case_when((time < intervention_lift) ~1,
                                                 (time>=intervention_lift) ~ linear(times, mscale=max_scales[3])),
                scale_beta_4 = case_when((time < intervention_lift) ~1,
                                                 (time>=intervention_lift) ~ linear(times, mscale=max_scales[4])),
                scale_beta_5 = case_when((time < intervention_lift) ~1,
                                                 (time>=intervention_lift) ~ linear(times, mscale=max_scales[5])),
               add_noise_to_beta = case_when((time < intervention_lift) ~ 0,
                                             (time >= intervention_lift) ~ 1))
    
    row.names(raw_scales) = raw_scales$time
    raw_scales
    
}


get_scale_linear_special = function(
                     intervention_lift,
                     intervention_reinstate,
                     simstart,
                     simend,
                     max_scales,
                     tm = as.Date('2020-07-01')
                     ){
    
    times = seq(1, simend, 1)
    
    linear = function(x, mscale, tmax=as.Date(tm)){
        slope = (mscale - 1) / (as.numeric(tmax - as.Date('2020-01-14')) - intervention_lift)
        mean = slope * (x-intervention_lift) + 1
        mean = if_else(mean >= mscale, mscale, mean)
        mean
    }


    raw_scales = data.frame(time=times, 
                            scale_beta_1=1,
                            scale_beta_2=1,
                            scale_beta_3=1,
                            scale_beta_4=1,
                            scale_beta_5=1) %>%
        mutate(scale_beta_1 = case_when((time < intervention_lift | time >= intervention_reinstate) ~1,
                                                 (time>=intervention_lift & time < intervention_reinstate) ~ linear(times, mscale=max_scales[1])),
                scale_beta_2 = case_when((time < intervention_lift | time >= intervention_reinstate) ~1,
                                                 (time>=intervention_lift & time < intervention_reinstate) ~ linear(times, mscale=max_scales[2])),
                scale_beta_3 = case_when((time < intervention_lift | time >= intervention_reinstate) ~1,
                                                 (time>=intervention_lift & time < intervention_reinstate) ~ linear(times, mscale=max_scales[3])),
                scale_beta_4 = case_when((time < intervention_lift | time >= intervention_reinstate) ~1,
                                                 (time>=intervention_lift & time < intervention_reinstate) ~ linear(times, mscale=max_scales[4])),
                scale_beta_5 = case_when((time < intervention_lift | time >= intervention_reinstate) ~1,
                                                 (time>=intervention_lift & time < intervention_reinstate) ~ linear(times, mscale=max_scales[5])),
               add_noise_to_beta = case_when((time < intervention_lift) ~ 0,
                                             (time >= intervention_lift) ~ 1))
    
    row.names(raw_scales) = raw_scales$time
    raw_scales
    
}


