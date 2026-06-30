const User = require("../models/User");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

exports.registerUser = async(req,res)=>{

 try{

  const {username, name, phone, password} = req.body;

  if (!username || !/^[a-zA-Z0-9_]{4,20}$/.test(username)) {
    return res.status(400).json({message: "Username must be 4-20 characters long and can only contain letters, numbers, and underscores"});
  }

  const existingUsername = await User.findOne({username});
  if (existingUsername) {
    return res.status(400).json({message: "Username already exists"});
  }

  const hashedPassword = await bcrypt.hash(password,10);

  const user = new User({
    username,
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

  const {identifier, password} = req.body;

  if (!identifier) {
    return res.status(400).json({message: "Username or Phone number is required"});
  }

  const user = await User.findOne({
    $or: [{ username: identifier }, { phone: identifier }]
  });

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