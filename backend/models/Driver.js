const mongoose = require("mongoose");

const driverSchema = new mongoose.Schema({

    name:{
        type:String,
        required:true
    },

    phone:{
        type:String,
        required:true,
        unique:true
    },

    bikeNumber:{
        type:String,
        required:true
    },

    available:{
        type:Boolean,
        default:true
    },

    location:{
        lat:{
            type:Number,
            default:0
        },
        lng:{
            type:Number,
            default:0
        }
    }

},{timestamps:true});

module.exports = mongoose.model("Driver",driverSchema);