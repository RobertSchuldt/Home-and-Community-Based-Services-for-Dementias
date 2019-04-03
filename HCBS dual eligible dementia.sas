/*************************************************************************************************************************************

This project is moving beyond the old POSTER B project and is adding in aspects of the PQI program provided by the AHRQ to 
determine preventable hospitalizations. This will be turned into an academic article. Increased efficiency of programming adapted into
this iteration of the project. Removed from the old POSTER B project because we are not focused on development of visualizations at this 
time and will focus more on analysis. 

@author: Robert F Schuldt
@email: rschuldt@uams.edu

**************************************************************************************************************************************/

libname cms '*********************';
libname poster '*********************';
libname zip '************************';


/*Calling in my macro program for sorting*/
%include '************************';

/*Now I start with the raw CCW file and select the variables I will need for this project*/

data mbsf_file;
	set cms.mbsf_abcd_summary;
	if STATE_CODE in ('54', '55','56', '57','58','59','60','61','62','63','97','98','99') then delete;

	/*** There is no change amongst the Fips County Code from Jan to December for all patients, so we can just use this. Do not need
	to merge in the SSA to FIPS crosswalk, because we already have it***/
	fips = substr(STATE_CNTY_FIPS_CD_01, 1, 2);
	if fips = 99 then delete;
	fips_state = fipstate(fips);
	** Age marker **;

	age = AGE_AT_END_REF_YR;
	if AGE_AT_END_REF_YR lt 65 then delete;

	**Generatingsex  variable 2 = female**;
	if SEX_IDENT_CD = '2' then sex = 2;
	if SEX_IDENT_CD = '1' then sex = 1;

	if DUAL_ELGBL_MONS = 12 then dual = 1;
		else dual = 0;
	if (DUAL_ELGBL_MONS ge 1 and DUAL_ELGBL_MONS lt 12) then part_dual = 1;
		else part_dual = 0;

	if BENE_HMO_CVRAGE_TOT_MONS = 0 then ffs= 1;
		else ffs = 0;
	zip = ZIP_CD; 
		run;

data dual;
	set mbsf_file;
	where dual = 1 and ( STATE_CODE ne "06" and STATE_CODE ne "34")  ;

run;


data oasis_a;
	set cms.combined_oasis;
	where M0100_ASSMT_REASON = "01" and M0110_EPSD_TIMING_CD = '01';
run;


proc sort data= oasis_a out = sorted_oasis;
by bene_id ASMT_EFF_DATE ;
run;
/*Keep the first observation of the patients*/
proc sort data = sorted_oasis out = first_oasis nodupkey;
by bene_id;
run;

%sort(dual, bene_id)
%sort(first_oasis, bene_id)

data poster_b;
	merge dual (in = a) first_oasis (in = b);
	by bene_id;
	if a;
	if b;
run;

/*Time to pull in the merged PQI data that contains the preventable hospilizations that we used the software for*/

libname pqi '************************';
data pqi;
	set pqi.medpar_pqi;
		drop PTC_PBP_ID_01-PTC_PBP_ID_12 PTC_PLAN_TYPE_CD_01-PTC_PLAN_TYPE_CD_12;
run;
	
/*Now I merge with OASIS data so I can actually have the final set of patients I am looking for*/

%sort(pqi, bene_id)
%sort(poster_b, bene_id)

data pqi_oasis (compress = yes);
 merge poster_b (in = a) pqi (in = b);
 by bene_id;
 if a;
 	run;
/* Saving data set onto drive here so I do not need to rerun the program for any future work with the data sets
	I am identifying if any of the conditions listed below has a value of 1 so we can identify any preventable hospitlizations
	and then identifying it in relation to the SOC date for home health. Was it before or after */
data poster.full_set;
	set pqi_oasis;
		if M0030_SOC_DT lt '01JAN2015'd or M0030_SOC_DT gt '01DEC2015'd then delete;
			%let prev = TAPQ01 TAPQ02 TAPQ03 TAPQ05 TAPQ07 TAPQ08 TAPQ10 TAPQ11 TAPQ12 TAPQ14 TAPQ15 TAPQ16;
				array cond  &prev;
					do over cond;
						if cond = 1 then preventable_hosp = 1;
					end;
		
			/*Identify whether the stay is a short or long stay or snf*/
			
			if SS_LS_SNF_IND_CD = "S" then hosp_stay = 1;
				else hosp_stay = 0;
			if SS_LS_SNF_IND_CD = "N" or SS_LS_SNF_IND_CD = "L" then nh_stay = 1;
				else nh_stay = 0;

			if SS_LS_SNF_IND_CD = "S" or SS_LS_SNF_IND_CD = "N" or SS_LS_SNF_IND_CD = "L" then any_hosp_stay = 1;
				else any_hosp_stay = 0;
			/* Time to identify the types of prevents*/

			%let ph = preventable_hosp;
			soc_plus = M0030_SOC_DT+30;

			if (ADMSN_DT gt M0030_SOC_DT and ADMSN_DT lt soc_plus) and &ph = 1 then acsc_hha = 1;
				else acsc_hha = 0;

			if (ADMSN_DT ge M0030_SOC_DT and ADMSN_DT lt soc_plus) and nh_stay = 1 then nh_hha = 1;
				else nh_hha = 0;
	run;

					
proc freq data= poster.full_set;
table       M0100_ASSMT_REASON ;
run;

/*Import HCBS data*/

proc import datafile = "************************"
dbms = xlsx out = hcbs replace;
run;
proc import datafile = "************************"
dbms = xlsx out = kff replace;
run;
%sort(kff, fips_state)
%sort(hcbs, fips_state)




/*Merging the data together so I can get the aged disabled population then divide by the total HCBS spending*/
data generosity;
	merge hcbs (in = a) kff (in = b);
	by fips_state;
	if a;
	if b;
	run;
run;
data poster.generosity;
	set generosity;
		keep hcbs_rate low_generosity mod_generosity high_generosity fips_state;

	hcbs_rate = Total_HCBS/Total_Aged_Disabled;

	if hcbs_rate lt 3.34 then low_generosity = 1;
		else low_generosity = 0;
	if hcbs_rate ge 3.34 and  hcbs_rate lt 6.64 then mod_generosity = 1;
		else mod_generosity = 0;
	if hcbs_rate ge 6.64 then high_generosity = 1;
		else high_generosity = 0;

run;

proc univariate;
var hcbs_rate;
run;
proc freq data = poster.generosity;
table high_generosity;
run;


/*Now we must bring the HCBS data with its generosity into the actual CMS data set*/

%sort(poster.full_set, fips_state);
%sort(poster.generosity, fips_state);
proc freq data = poster.full_set;
table fips_state;
run;

data hcbs_pqi;
	merge poster.full_set (in = a)poster.generosity(in = b);
	by fips_state;
	if a;
	if b;
run;
ods rtf file= '************************'
contents = yes;
proc freq data = poster.data_dementiasubset;
table M2430: ;
run;
ods rtf close;
data poster.data_dementiasubset;
	set hcbs_pqi;
	
	/**Generating female variable**/

	if sex = 2 then female = 1;
		else female = 0;

white = 0;
	if rti_race_cd = '1' then white = 1;
	if rti_race_cd = '0' then white = .;

	black = 0;
	if rti_race_cd = '2' then black = 1;
	if rti_race_cd = '0' then black = .;

	hispanic = 0;
	if rti_race_cd = '5' then hispanic = 1;
	if rti_race_cd = '0' then hispanic = .;

	other_race = 0;
	if rti_race_cd = '3' then other_race = 1;
	if rti_race_cd = '4' then other_race = 1;
	if rti_race_cd = '6' then other_race = 1;
	if rti_race_cd = '0' then other_race = .;


/*This is all older code that is being brought in to make changse to the OASIS data for final analysis. I could
		recode this to be more efficient, but if it isn't broke don't fix it at this point*/
		if M1020_PRI_DGN_SEV = "02" then p_sever_mid = 1;
			else p_sever_mid = 0;
		if M1020_PRI_DGN_SEV = "03" or M1020_PRI_DGN_SEV = "04" then p_sever_high = 1;
			else p_sever_high = 0;
	
	 	nd_sever_high = 0;
	 		if M1022_OTH_DGN1_SEV = "03" then nd_sever_high = 1;
			if M1022_OTH_DGN2_SEV = "03" then nd_sever_high = 1;
			if M1022_OTH_DGN3_SEV = "03" then nd_sever_high = 1;
			if M1022_OTH_DGN4_SEV = "03" then nd_sever_high = 1;
			if M1022_OTH_DGN5_SEV = "03" then nd_sever_high = 1;
	 		
			if M1022_OTH_DGN1_SEV = "04" then nd_sever_high = 1;
			if M1022_OTH_DGN2_SEV = "04" then nd_sever_high = 1;
			if M1022_OTH_DGN3_SEV = "04" then nd_sever_high = 1;
			if M1022_OTH_DGN4_SEV = "04" then nd_sever_high = 1;
			if M1022_OTH_DGN5_SEV = "04" then nd_sever_high = 1;

		nutrition = 0;
		if M1030_THH_ENT_NUTR = "1" then nutrition = 1;
		if M1030_THH_IV_INFUS  = "1" then nutrition = 1;
		if M1030_THH_NONE_ABV  = "1" then nutrition = 0;
		if M1030_THH_PAR_NUTR  = "1" then nutrition = 1;

		stable = 0;
		if M1034_PTNT_OVRAL_STUS = '00' then stable = 1;
		if M1034_PTNT_OVRAL_STUS = '01' then stable = 1;
		if M1034_PTNT_OVRAL_STUS = '.' then stable = .;

		 
		risk = 0;
		if M1036_RSK_Alcohol = '1' then risk = 1;
		if M1036_RSK_drugs = '1' then risk = 1; 
		if M1036_RSK_obesity =  '1' then risk = 1;
		if M1036_RSK_smoking = '1' then risk = 1;
		if M1036_RSK_uk = '1' then risk = .;

		alone_0 = 0;
		if M1100_PTNT_LVG_STUTN = "05" then alone_0 = 1;

		alone_ass = 0;
		if M1100_PTNT_LVG_STUTN = "01" then alone_ass = 1;
		if M1100_PTNT_LVG_STUTN = "02" then alone_ass = 1;
		if M1100_PTNT_LVG_STUTN = "03" then alone_ass = 1;
		if M1100_PTNT_LVG_STUTN = "04" then alone_ass = 1;

		pain1 = 0;
		if M1242_PAIN_FREQ_ACTVTY_MVMT = '02' then pain1 = 1;
		if M1242_PAIN_FREQ_ACTVTY_MVMT = '03' then pain1 = 1;

		pain2 = 0;
		if M1242_PAIN_FREQ_ACTVTY_MVMT = '04' then pain2 = 1;

		if M1306_UNHLD_stg2_prsr_ulcr = "1" then ulcer2_up = 1;
			else ulcer2_up = 0;

		surg_wd_lesion = 0;
		if m1340_srgcl_wnd_prsnt = "01" or m1340_srgcl_wnd_prsnt = "02" then surg_wd_lesion = 1;
		lesion = 0;
		if m1350_lesion_open_wnd = "1" then lesion = 1;

		dyspenic = 0;
		if m1400_when_dyspnic = "02" or m1400_when_dyspnic = "03" or m1400_when_dyspnic = "04" then dyspenic = 1;
		
		respritory = 0;
		if m1410_resptx_airpr = "1" then respritory = 1;
 		if m1410_resptx_oxygn  = "1" then respritory = 1;
		if m1410_resptx_vent = "1" then respritory = 1;

		uti = 0;
		if  M1600_uti = "01" then uti = 1;
		if   M1600_uti   = "." or  M1600_uti  = "UK" then uti = .;
		
	
		if m1615_incntnt_timing = "02" or m1615_incntnt_timing = "03" or m1615_incntnt_timing = "04" then u_incntn = 1;
			else u_incntn = 0;
		if m1620_bwl_incont = "02" or m1620_bwl_incont = "03" or m1620_bwl_incont ="04" or m1620_bwl_incont = "05" then bwl_incntn = 1;
			else bwl_incntn = 0;

		if m1700_cog_function = "01" or m1700_cog_function = "02" then cog_fun_mild = 1;
			else cog_fun_mild = 0;

		if m1700_cog_function = "03" or m1700_cog_function = "04" then cog_fun_high = 1;
			else cog_fun_high = 0;

		if  m1730_phq2_dprsn = "01" THEN depression_mid = 1;
			else depression_mid = 0;
		if  m1730_phq2_dprsn = "NA" THEN depression_mid = .;

		if  m1730_phq2_dprsn = "02" or  m1730_phq2_dprsn = "03" THEN depression_high = 1;
			else depression_high = 0;
		if  m1730_phq2_dprsn = "NA" THEN depression_high = .;
		
		d_impaired = 0; 
		if m1740_bd_delusions = "1" then bd_impaired = 1;
		if m1740_bd_imp_dcsn  = "1" then bd_impaired = 1;
		if m1740_bd_mem_dfict   = "1" then bd_impaired = 1;
		if m1740_bd_physical  = "1" then bd_impaired = 1;
		if m1740_bd_soc_inapp = "1" then bd_impaired = 1;
		if m1740_bd_delusions = "1" then bd_impaired = 1;
		if m1740_bd_verbal = "1" then bd_impaired = 1;

		if M1000_DC_IPPS_14_DA = "1" then pac_hosp = 1; 
			else pac_hosp = 0;
		if M1000_DC_NON_14_DA = "1" then community = 1;
			else community = 0;
		
		pac_other = 0;
		if M1000_DC_IRF_14_DA = "1" then pac_other = 1;
        if M1000_DC_LTC_14_DA = "1" then pac_other = 1;
		if M1000_DC_LTCH_14_DA = "1" then pac_other = 1;
		if M1000_DC_OTH_14_DA = "1" then pac_other = 1;
		if M1000_DC_PSYCH_14_DA = "1" then pac_other = 1; 
		if M1000_DC_SNF_14_DA = "1" then pac_other = 1;

		
	if m1800_cu_grooming = "01" or m1800_cu_grooming = "02" or m1800_cu_grooming = "03" then groom = 1;
		else groom = 0;

	if m1810_cu_dress_upr = "01" or m1810_cu_dress_upr = "02" or m1810_cu_dress_upr = "03" then dress_up = 1;
		else dress_up = 0;

	if m1820_cu_dress_low = "01" or m1820_cu_dress_low = "02" or m1820_cu_dress_low = "03" then dress_down = 1;
		else dress_down = 0;

	if m1830_crnt_bathg = "02" or m1830_crnt_bathg = "03" or m1830_crnt_bathg = "04" or m1830_crnt_bathg = "05" then bath = 1;
		else bath = 0;

	if m1840_cur_toiltg = "01" or m1840_cur_toiltg = "02" or m1840_cur_toiltg = "03" or m1840_cur_toiltg = "04" then toliet = 1;
		else toliet = 0;

	if m1845_cur_toiltg_hygn = "01" or m1845_cur_toiltg_hygn = "02"  or m1845_cur_toiltg_hygn = "03" then hygiene = 1;
		else hygiene = 0;
 
	if m1850_cur_trnsfrng = "02" or m1850_cur_trnsfrng = "03" or m1850_cur_trnsfrng= "04" or m1850_cur_trnsfrng = "05" then transfer = 1;
		else transfer = 0;

	if m1860_crnt_ambltn = "02" or m1860_crnt_ambltn = "03" or m1860_crnt_ambltn = "04" or m1860_crnt_ambltn = "05" or m1860_crnt_ambltn = "06" then ambu = 1;
		else ambu = 0;

	if m1870_cu_feeding = "01" or m1870_cu_feeding = "02" or m1870_cu_feeding = "03" or m1870_cu_feeding = "04" or m1870_cu_feeding = "05" then feeding = 1;
		else feeding = 0;

	if m1910_mlt_fctr_fall_risk_asmt = "02" then fall_risk = 1;
		else fall_risk = 0;

	adl_sum = sum(groom, dress_up, dress_down, bath , toliet, transfer, ambu, feeding);

	%include '************************';
/*I could have built a macro to search through the diagnosis to find who had dementia, but I was tired. I used this simple 
	way to get the program prepped for running overnight */
		array dg &inpatdiag;
		
			do over dg ;
			
			alzheimer = 0;
			if substr(dg, 1, 3) = "331" and ADMSN_DT lt '01OCT2015'd then alzheimer = 1;
			if substr(dg, 1, 3) = "G30" and ADMSN_DT ge '01OCT2015'd then alzheimer = 1;
			
			dementia = 0;
			if substr(dg, 1, 3) = "290" and ADMSN_DT lt '01OCT2015'd then dementia = 1;
			if substr(dg, 1, 3) = "294" and ADMSN_DT lt '01OCT2015'd then dementia = 1;

			if substr(dg, 1, 3) = "F01" and ADMSN_DT ge '01OCT2015'd then dementia = 1;
			if substr(dg, 1, 3) = "F02" and ADMSN_DT ge '01OCT2015'd then dementia = 1;
			if substr(dg, 1, 3) = "F03" and ADMSN_DT ge '01OCT2015'd then dementia = 1;
			if substr(dg, 1, 3) = "F05" and ADMSN_DT ge '01OCT2015'd then dementia = 1;

			end;

		array dg2 &outpatdiag;
			do over dg2;

			if substr(dg2, 1, 3) = "331" and M0030_SOC_DT lt '01OCT2015'd then alzheimer = 1;
			if substr(dg2, 1, 3) = "G30" and M0030_SOC_DT ge '01OCT2015'd then alzheimer = 1;

			if substr(dg2, 1, 3) = "290" and M0030_SOC_DT lt '01OCT2015'd then dementia = 1;
			if substr(dg, 1, 3) = "294" and M0030_SOC_DT lt '01OCT2015'd then dementia = 1;

			if substr(dg2, 1, 3) = "F01" and M0030_SOC_DT ge '01OCT2015'd then dementia = 1;
			if substr(dg2, 1, 3) = "F02" and M0030_SOC_DT ge '01OCT2015'd then dementia = 1;
			if substr(dg2, 1, 3) = "F03" and M0030_SOC_DT ge '01OCT2015'd then dementia = 1;
			if substr(dg2, 1, 3) = "F05" and M0030_SOC_DT ge '01OCT2015'd then dementia = 1;

			end;



	run;




	data selected_variables (compress = yes);
		set poster.data_dementiasubset;
			where dementia = 1 or alzheimer = 1;
			if m1700_cog_function = "00" then delete;
			if high_generosity = 1 then gener = 2;
			if mod_generosity = 1 then gener = 1;
			if low_generosity = 1 then gener = 0;
run;

proc freq;
table acsc_hha dementia alzheimer;
run;


%sort(selected_variables, gener);
proc format;
value gen
2 = "High Generosity"
1 = "Moderate Generosity"
0 = "Low Generosity"
;
run;

title1 'Selected Variable Means and Standard Deviations';
goptions reset=all hsize=7in vsize=2in;

ods rtf file= '************************'
contents = yes;

title 'Table 1: Generosity Level by State';
proc freq data = selected_variables;
table fips_state;
by gener;
format gener gen.;
run;

%macro means(pqi);

proc sort data =selected_variables;
by &pqi;
run;

title 'Preventable Hospitalizations and Utlizations by &pqi';
proc means data = selected_variables n mean sum; 
var los MDCR_PMT_AMT;
by &pqi;
run;

title 'Preventable Hospitalizations and Utlizations by &pqi';
proc means data = selected_variables n mean sum; 

class gener;

var los MDCR_PMT_AMT;
by &pqi;
format gener gen.;
run;


%Mend means;
%means(TAPQ01)
%means(TAPQ02)
%means(TAPQ03)
%means(TAPQ05)
%means(TAPQ07)
%means(TAPQ08)
%means(TAPQ10)
%means(TAPQ11)
%means(TAPQ12)
%means(TAPQ14)
%means(TAPQ15)   
%means(TAPQ16)

%sort(selected_variables, gener)

title 'Table 3: Mean and Standard Deviation of Selected Variables';
proc means data = selected_variables mean std n;
var age female black hispanic other_race 
pac_hosp pac_other adl_sum p_sever_high p_sever_mid nutrition stable risk alone_0 pain1 
pain2 ulcer2_up surg_wd_lesion lesion dyspenic respritory uti u_incntn bwl_incntn cog_fun_mild
cog_fun_high depression_mid depression_high fall_risk;
run;

title 'Table 4: Regresion of Preventable Hospitalizations by HCBS';

proc surveylogistic data = selected_variables;
cluster M0010_MEDICARE_ID;
model acsc_hha (event = "1") = high_generosity mod_generosity low_generosity age female black hispanic other_race 
pac_hosp pac_other adl_sum p_sever_high p_sever_mid nutrition stable risk alone_0 pain1 
pain2 ulcer2_up surg_wd_lesion lesion dyspenic respritory uti u_incntn bwl_incntn cog_fun_mild
cog_fun_high depression_mid depression_high fall_risk;
run;


quit;
ods rtf close;

proc surveylogistic data = selected_variables;
cluster M0010_MEDICARE_ID;
model acsc_hha (event = "1") = high_generosity mod_generosity; 
run;

proc genmod data = selected_variables;
model acsc_hha = high_generosity mod_generosity /dist=zinb;
	zeromodel 



