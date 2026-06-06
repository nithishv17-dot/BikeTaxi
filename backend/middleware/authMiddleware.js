const jwt = require("jsonwebtoken");

module.exports = function(req,res,next){

 const authHeader = req.header("Authorization");

 if(!authHeader){
  return res.status(401).json({message:"No token"});
 }

 const token = authHeader.startsWith("Bearer ")
  ? authHeader.split(" ")[1]
  : authHeader;

 try{

  const decoded = jwt.verify(token,"secretkey");

  req.user = decoded;

  next();

 }catch(err){

  res.status(401).json({message:"Invalid token"});

 }

}
