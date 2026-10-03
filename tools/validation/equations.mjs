// Independent first-party SI algebra. No JSBSim imports, XML parser or observed trace.
export const inputKeys=['rho_kg_m3','tas_mps','alpha_rad','beta_rad','p_aero_rad_s','q_aero_rad_s','r_aero_rad_s','jsb_aileron','jsb_elevator','jsb_trim','jsb_rudder'];
export const outputKeys=['qbar_pa','qS_n','phat','qhat','rhat','CL','CD','CY','Cl','Cm','Cn','lift_wind_n','drag_wind_n','side_wind_n','roll_body_nm','pitch_body_nm','yaw_body_nm'];
export function evaluate(x) {
 const {rho_kg_m3:rho,tas_mps:v,alpha_rad:a,beta_rad:b,p_aero_rad_s:p,q_aero_rad_s:q,r_aero_rad_s:r,jsb_aileron:ail,jsb_elevator:e,jsb_trim:t,jsb_rudder:rud}=x;
 for(const key of inputKeys)if(typeof x[key]!=='number'||!Number.isFinite(x[key]))throw Error('Nonfinite equation input');
 if(rho<0||v<0)throw Error('Negative density/speed');
 const denom=Math.max(.6096,2*v),phat=p*10/denom,qhat=q*1.7/denom,rhat=r*10/denom;
 const qbar_pa=.5*rho*v*v,qS_n=qbar_pa*17,CL=.22+5*a,CD=.03+.08*a*a,CY=-.5*b+.15*rud,Cl=-.05*b-.6*phat+.08*ail,Cm=.02-a-8*qhat-.7*(e+t),Cn=.1*b-2*rhat-.08*rud;
 return {qbar_pa,qS_n,phat,qhat,rhat,CL,CD,CY,Cl,Cm,Cn,lift_wind_n:qS_n*CL,drag_wind_n:qS_n*CD,side_wind_n:qS_n*CY,roll_body_nm:qS_n*10*Cl,pitch_body_nm:qS_n*1.7*Cm,yaw_body_nm:qS_n*10*Cn};
}
export function unsignedTerms(x,values) {
 return {lift_wind_n:values.qS_n*(.22+Math.abs(5*x.alpha_rad)),drag_wind_n:values.qS_n*(.03+.08*x.alpha_rad**2),side_wind_n:values.qS_n*(Math.abs(.5*x.beta_rad)+Math.abs(.15*x.jsb_rudder)),
 roll_body_nm:values.qS_n*10*(Math.abs(.05*x.beta_rad)+Math.abs(.6*values.phat)+Math.abs(.08*x.jsb_aileron)),
 pitch_body_nm:values.qS_n*1.7*(.02+Math.abs(x.alpha_rad)+Math.abs(8*values.qhat)+Math.abs(.7*x.jsb_elevator)+Math.abs(.7*x.jsb_trim)),
 yaw_body_nm:values.qS_n*10*(Math.abs(.1*x.beta_rad)+Math.abs(2*values.rhat)+Math.abs(.08*x.jsb_rudder))};
}

// Standard wind-to-body rotation; positive drag/lift are negative wind X/Z.
export function bodyForce(x,e) {
 const ca=Math.cos(x.alpha_rad),sa=Math.sin(x.alpha_rad),cb=Math.cos(x.beta_rad),sb=Math.sin(x.beta_rad);
 return {
  x:-e.drag_wind_n*ca*cb-e.side_wind_n*ca*sb+e.lift_wind_n*sa,
  y:-e.drag_wind_n*sb+e.side_wind_n*cb,
  z:-e.drag_wind_n*sa*cb-e.side_wind_n*sa*sb-e.lift_wind_n*ca
 };
}
