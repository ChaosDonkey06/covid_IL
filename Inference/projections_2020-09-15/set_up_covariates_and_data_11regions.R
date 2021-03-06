# Create result directory if it doesn't exist
dir.create(file.path(output_dir), showWarnings = FALSE)

## Setting dates
print('Setting dates')
simstart = convert_date_to_time(simstart, t_ref)
simend = convert_date_to_time(simend, t_ref)
min_data_time = convert_date_to_time(min_data_time, t_ref)
intervention_start = convert_date_to_time(intervention_start, t_ref)
min_data_time_ICU = as.Date(min_data_time_ICU)

## Filenames
print('Reading in files')
initFile = covid_get_path(init_file)
rprocFile = covid_get_path(rprocFile)
dmeasFile = covid_get_path(dmeasFile)
rmeasFile = covid_get_path(rmeasFile)
fraction_underreported_file = covid_get_path(fraction_underreported_file)
contact_filename = covid_get_path(contact_filename)

## CSnippets
print('Reading in CSnippets')
dmeasure_snippet <- read_Csnippet(dmeasFile)
rprocess_snippet <- read_Csnippet(rprocFile)
rinit_snippet <- read_Csnippet(initFile)
rmeasure_snippet <- read_Csnippet(rmeasFile)
    
## Fraction underreported
print('Getting fraction underreported')
fraction_underreported = read.csv(fraction_underreported_file)
row.names(fraction_underreported) = fraction_underreported$time
# icu reporting

## Contact matrix as covariate table
print('Loading contact matrix')
pomp_contacts = read.csv(contact_filename)

## Population sizes
print('Reading in population info')
population_list=read.csv(covid_get_path(population11_file))
n_age_groups = 9

## User-specification of parameters and interventions for model 
print('Initializing parameters')
par_frame = read.csv(default_par_file)
pars = as.numeric(par_frame$value)
names(pars) = par_frame$param_name
pars = as.list(pars)

## Add in initial age distribution
age_dist_frame = read.csv(covid_get_path(age_dist_file)) 
temp_age_dist = age_dist_frame %>% 
  filter(b_elderly == pars$b_elderly) %>% select(-b_elderly)
age_dist = as.numeric(temp_age_dist$value)
names(age_dist) = temp_age_dist$param_name
pars = c(age_dist, pars)
pars$tmax = simend

## Add in covariates
print('Adding in covariates')
if (use_changepoint){
    beta_scales = NULL
} else{
    print('Reading transmission covariate')
    covarcols = paste0(beta_covariate_column, '_', 1:5)
    beta_scales = read.csv(covid_get_path(beta_covariate_file)) %>% 
        select(time, covarcols)    
}

print('Loading data')
region_order = as.character(1:pars$n_regions)
# Load real data, assume read in from civis
civis_data = read.csv(covid_region_data_filename)  %>% 
    mutate(Date=as.Date(date), 
        total_deaths = hosp_deaths+nonhosp_deaths,
        restore_region = covid_region) %>%
    select(-covid_region)

stopifnot('emr_deaths' %in% names(civis_data))

get_idph = function(date, region){
    idph[which(idph$Date==date & idph$region==region), 'new_deaths']
}

# Add idph total deaths to total deaths
idph = read.csv(idph_filename) %>% 
    mutate(Date=as.Date(date), region=new_restore_region) %>%
    select(Date, region, new_deaths)

df = civis_data %>% mutate(
    source=case_when((is.na(total_deaths)) ~ 'Public',
                     (!is.na(total_deaths))~ 'IDPH line list'),
    total_deaths=case_when((is.na(total_deaths)) ~ as.numeric(mapply(get_idph, Date, restore_region)),
                           (!is.na(total_deaths))~ as.numeric(total_deaths))) %>%
    mutate(time = as.numeric(Date - as.Date(t_ref))) %>%
    group_by(restore_region) %>%
    mutate(
           date=Date) %>%
    ungroup() %>%
    select(restore_region, confirmed_covid_icu, covid_non_icu, total_deaths, emr_deaths, date) %>%
    mutate(confirmed_covid_icu = if_else(confirmed_covid_icu < 0, 0, round(confirmed_covid_icu)),
           total_deaths = if_else(total_deaths < 0, 0, round(total_deaths)),
           covid_non_icu = if_else(covid_non_icu < 0, 0, round(covid_non_icu)),
           emr_deaths = if_else(emr_deaths < 0, 0, round(emr_deaths)))


df_ICU = df %>% select(date, restore_region, confirmed_covid_icu) %>% 
    spread(restore_region, confirmed_covid_icu) %>% 
    select(date, region_order) %>% 
    filter(date>=min_data_time_ICU)
names(df_ICU) = c('time', paste0('ObsICU_', 1:pars$n_regions))

df_death = df %>% 
    select(date, restore_region, total_deaths) %>% 
    spread(restore_region, total_deaths) %>% 
    select(date, region_order)
names(df_death) = c('time', paste0('ObsDeaths_', 1:pars$n_regions))

df_hosp = df %>% 
    select(date, restore_region, covid_non_icu) %>% 
    spread(restore_region, covid_non_icu) %>% 
    select(date, region_order)
names(df_hosp) = c('time', paste0('ObsHosp_', 1:pars$n_regions))

df_emr_deaths = df %>% 
    select(date, restore_region, emr_deaths) %>% 
    spread(restore_region, emr_deaths) %>% 
    select(date, region_order)
names(df_emr_deaths) = c('time', paste0('ObsHospDeaths_', 1:pars$n_regions))


data = left_join(df_death, df_ICU, by='time')
data = left_join(data, df_hosp, by='time')
data = left_join(data, df_emr_deaths, by='time')
data$time = as.numeric(as.Date(data$time) - as.Date(t_ref))

stopifnot(max(data$time) >= simend)

data = data %>% filter(time <= simend)
print(tail(data))

print('Set up parameter transformation')
observed_names=names(data %>% select(-time))
observed_names = c(paste0('ObsICU_', 1:pars$n_regions), 
    paste0('ObsDeaths_', 1:pars$n_regions), 
    paste0('ObsHosp_', 1:pars$n_regions), 
    paste0('ObsHospDeaths_', 1:pars$n_regions))

if (use_changepoint){
    transformation=parameter_trans(
    log=c(
    'beta2_1',
    'beta2_2',
    'beta2_3',
    'beta2_4',
    'beta2_5',
    'scale_phase3_1',
    'scale_phase3_2',
    'scale_phase3_3',
    'scale_phase3_4',
    'scale_phase3_5',
    'scale_phase4_1',
    'scale_phase4_2',
    'scale_phase4_3',
    'scale_phase4_4',
    'scale_phase4_5',  
    'beta1_1',
    'beta1_2',
    'beta1_3',
    'beta1_4',
    'beta1_5'),
    logit=c('num_init_1',
    'num_init_2',
    'num_init_3',
    'num_init_4',
    'num_init_5')
    )
} else{
    transformation=parameter_trans(
    log=c(
    'beta1_1',
    'beta1_2',
    'beta1_3',
    'beta1_4',
    'beta1_5'),
    logit=c('num_init_1',
    'num_init_2',
    'num_init_3',
    'num_init_4',
    'num_init_5')
    )

}


