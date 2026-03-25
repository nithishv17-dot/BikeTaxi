const User = require("../models/User");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

exports.registerUser = async(req,res)=>{

 try{

  const {name,phone,password} = req.body;

  const hashedPassword = await bcrypt.hash(password,10);

  const user = new User({
    name,
    phone,
    password:hashedPassword
  });

  await user.save();

  res.json({message:"User registered"});

 }catch(err){

  res.status(500).json({error:err.message});

 }

};


exports.loginUser = async(req,res)=>{

 try{

  const {phone,password} = req.body;

  const user = await User.findOne({phone});

  if(!user){
   return res.status(400).json({message:"User not found"});
  }

  const match = await bcrypt.compare(password,user.password);

  if(!match){
   return res.status(400).json({message:"Invalid password"});
  }

  const token = jwt.sign(
   {id:user._id},
   "secretkey",
   {expiresIn:"7d"}
  );

  res.json({
   token,
   user:{
    id:user._id,
    name:user.name
   }
  });

 }catch(err){

  res.status(500).json({error:err.message});

 }

};